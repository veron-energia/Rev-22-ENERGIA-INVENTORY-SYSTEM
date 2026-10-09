-- 414: an affiliate's deduction marked as settled.
--
-- Since 410 an affiliate whose commission was paid out and then taken back
-- owes it back, recovered from their later commission, and nothing recorded
-- that such a debt was settled some other way. The Owner decided on 9 Oct
-- 2026: "Mark as settled" (Owners and Managers): paid back to us, written
-- off, or paid off outside the app; an amount (at most the deduction), the
-- date it was settled and a note; its own audited record, voided (never
-- deleted) when it was a mistake. This suite builds production's case of
-- 9 Oct 2026 with invented data (September: earned 1705.59, adjustments
-- -991.64, paid 1276.30; October: earned 100.80, paid 93.72: S$555.27 owed
-- back), reads every figure each page reads before 414 (section 1), applies
-- 414 (the same figures, a re-run that changes nothing, the grants), then:
-- the refusals (who may, amount, date, how, note); a settlement and every
-- page's figure after it; a retry and a second click; a part settled, a
-- void and every figure back as it was; commission earned later is paid as
-- before; settlements beyond what is owed back once a take-back is lowered
-- (shown under review, and no payout recorded against that month, by the
-- page or the API); settlements are never deleted or rewritten; the portal
-- never shows the note; the audit rows.
--
-- Disposable database only; everything is rolled back. The migration is
-- applied inside this transaction, so run the file on its own:
--   psql -X -v ON_ERROR_STOP=1 -f scripts/commissions/tests/deduction-settlement.sql
-- It needs production's functions with 406 to 413 (414 refuses otherwise);
-- on a local database that has drifted from production, pass a file that
-- installs them, run right after the begin below:
--   psql -X -v ON_ERROR_STOP=1 -v prelude=/path/to/prod_prelude.sql -f ...
-- Every name, phone and email is invented (T414, +65914140xx, @sig.invalid).
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
\if :{?prelude}
\i :prelude
\endif

create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin if ok is distinct from true then raise exception 'FAIL: %', msg; end if; raise notice 'PASS  %', msg; end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;

-- Run p_sql as one of the fixture's logins (a key in fx), 'anon' (the public
-- key, signed out) or 'server' (no request: the SQL editor, pg_cron). Says
-- 'ok', a tab and the result; or the SQLSTATE, a tab and the message. What a
-- refused call wrote is undone.
create function pg_temp.call_as(p_who text, p_sql text) returns text language plpgsql as $f$
declare v_out text; v_state text; v_msg text; v_sub uuid := pg_temp.fx(p_who);
begin
  begin
    perform set_config('request.jwt.claim.sub', '', true);
    if p_who = 'server' then
      perform set_config('request.jwt.claims', '', true);
    elsif p_who = 'anon' then
      perform set_config('request.jwt.claims', '{"role":"anon"}', true);
      execute 'set local role anon';
    else
      perform set_config('request.jwt.claims', json_build_object('sub', v_sub, 'role', 'authenticated')::text, true);
      execute 'set local role authenticated';
    end if;
    execute p_sql into v_out;
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    return 'ok' || chr(9) || coalesce(v_out, '');
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    return v_state || chr(9) || v_msg;
  end;
end $f$;
-- The answer of a call that must succeed, as jsonb.
create function pg_temp.ok_as(p_who text, p_sql text) returns jsonb language plpgsql as $f$
declare v text := pg_temp.call_as(p_who, p_sql);
begin
  if split_part(v, chr(9), 1) <> 'ok' then raise exception 'FAIL: % as % was refused: %', p_sql, p_who, v; end if;
  return nullif(substr(v, 4), '')::jsonb;
end $f$;
-- The page's call to Mark as settled, as SQL.
create function pg_temp.settle_sql(p_ref text, p_amount numeric, p_on date, p_method text, p_note text, p_request uuid)
returns text language sql as $f$
  select format('select public.record_affiliate_deduction_settlement(%L, %s, %L, %L, %L, %L)::text',
                pg_temp.fx(p_ref), coalesce(p_amount::text, 'null'), p_on, p_method, p_note, p_request) $f$;
create function pg_temp.commission(ref text, inv text, amt numeric, on_day date) returns uuid language sql as $$
  insert into public.commissions(invoice_id, buyer_customer_id, referrer_customer_id, tier, product_type,
                                 line_amount, rate, commission_amount, invoice_paid_date, status)
  values (pg_temp.fx(inv), pg_temp.fx('buyer'), pg_temp.fx(ref), 'tier1', 'own', amt * 10, 10, amt, on_day, 'earned')
  returning id $$;
create function pg_temp.takeback(ref text, inv text, of_row text, amt numeric, on_day date) returns uuid language sql as $$
  insert into public.commissions(invoice_id, buyer_customer_id, referrer_customer_id, tier, product_type, line_amount,
                                 rate, commission_amount, invoice_paid_date, status, adjusts_commission_id, reversal_reason)
  values (pg_temp.fx(inv), pg_temp.fx('buyer'), pg_temp.fx(ref), 'tier1', 'own', amt * 10, 10, amt, on_day, 'earned',
          pg_temp.fx(of_row), 'Future payout adjustment: T414 fixture')
  returning id $$;
-- A payout is paid on the 2nd of the month after its commission month (never
-- after today): a1's September payout on 2 Oct 2026, as on production.
create function pg_temp.pay(ref text, m date, amt numeric) returns jsonb language sql as $$
  select pg_temp.ok_as('owner', format('select public.record_affiliate_payout(%L, %L, %s, %L, %L, %L, null, %L)::text',
           pg_temp.fx(ref), m, amt, pg_temp.fx('cash'), least(public.sg_today(), (m + interval '1 month 1 day')::date), 'T414', gen_random_uuid())) $$;

-- An internal function (the service role's alone), read by the database
-- owner with the Owner's id as the caller (affiliate_directory answers
-- Owners, Managers and Admins only).
create function pg_temp.as_owner_server(p_sql text) returns jsonb language plpgsql as $f$
declare v text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.fx('owner'), 'role', 'authenticated')::text, true);
  execute p_sql into v;
  perform set_config('request.jwt.claims', '', true);
  return v::jsonb;
end $f$;
-- Every figure a page reads about one affiliate. p_core leaves out what 414
-- adds, so the figures before and after 414 can be compared.
create function pg_temp.figures(p_ref text, p_core boolean) returns jsonb language plpgsql as $f$
declare v_id uuid := pg_temp.fx(p_ref); o jsonb; ov jsonb; v jsonb;
begin
  o := jsonb_build_object(
    'months', (select jsonb_agg(case when p_core then to_jsonb(b) - 'settled' else to_jsonb(b) end order by b.month)
                 from public.affiliate_month_balances() b where b.referrer = v_id),
    'netted', (select to_jsonb(r) from public.affiliate_referrer_balances() r where r.referrer = v_id));
  ov := pg_temp.ok_as('owner', 'select public.affiliate_payout_overview()::text');
  o := o || jsonb_build_object(
    'overview_months', (select jsonb_agg(case when p_core then g - 'settled' else g end order by g->>'month')
                          from jsonb_array_elements(ov->'groups') g where g->>'referrer' = v_id::text),
    'overview_affiliate', (select g from jsonb_array_elements(ov->'referrers') g where g->>'referrer' = v_id::text),
    'directory', (select g - 'name' from jsonb_array_elements(pg_temp.ok_as('owner', 'select public.affiliate_admin_directory()::text')) g
                   where g->>'customer_id' = v_id::text),
    'referrers_tab', pg_temp.ok_as('owner', format('select to_jsonb(x.unpaid_earned)::text from public.referrer_list() x where x.customer_id = %L', v_id)),
    'staff_directory', pg_temp.as_owner_server(format('select to_jsonb(d.unpaid_payable)::text from public.affiliate_directory() d where d.customer_id = %L', v_id)));
  v := pg_temp.ok_as('owner', format('select public.referrer_earnings(%L)::text', v_id));
  o := o || jsonb_build_object('referrer_detail', case when p_core
         then jsonb_build_object('lifetime', (v->'lifetime') - 'settled',
                                 'monthly', (select jsonb_agg(m - 'settled') from jsonb_array_elements(v->'monthly') m))
         else jsonb_build_object('lifetime', v->'lifetime', 'monthly', v->'monthly') end);
  v := pg_temp.ok_as('owner', format('select to_jsonb(x)::text from public.report_affiliates() x where x.customer_id = %L', v_id));
  o := o || jsonb_build_object('reports', case when p_core then v - 'settled' else v end);
  if pg_temp.fx(p_ref || '_login') is not null then
    v := pg_temp.ok_as(p_ref || '_login', 'select public.affiliate_portal_earnings()::text');
    o := o || jsonb_build_object('portal', case when p_core then (v->'summary') - 'settled' else v->'summary' end,
      'portal_dashboard', case when p_core
         then (pg_temp.ok_as(p_ref || '_login', 'select public.affiliate_portal_dashboard()::text')->'earnings') - 'settled'
         else pg_temp.ok_as(p_ref || '_login', 'select public.affiliate_portal_dashboard()::text')->'earnings' end);
  end if;
  if not p_core then
    v := pg_temp.ok_as('owner', 'select public.dashboard_summary()::text');
    o := o || jsonb_build_object('dashboard', jsonb_build_object('unpaid_commission', v->'unpaid_commission',
                                                                 'commission_deductions', v->'commission_deductions'));
  end if;
  return o;
end $f$;
create temp table snap(k text primary key, v jsonb);

-- ===== Fixtures =====
do $$
declare v uuid; k text; n int := 0;
begin
  perform set_config('request.jwt.claims', '', true);
  foreach k in array array['owner','manager','admin','staff','inactive','nostaff','a1_login','a2_login'] loop
    insert into auth.users(id, email) values (gen_random_uuid(), 't414-' || replace(k, '_', '-') || '@sig.invalid') returning id into v;
    insert into fx values (k, v);
  end loop;
  insert into public.profiles(id, full_name, email, role, is_active)
  select pg_temp.fx(x.k), 'T414 ' || initcap(x.k), 't414-' || x.k || '@sig.invalid', x.role::public.user_role, x.active
    from (values ('owner','owner',true), ('manager','manager',true), ('admin','admin',true),
                 ('staff','staff',true), ('inactive','manager',false)) x(k, role, active);
  insert into public.stores(name, code, country_code) values ('T414 Store', 'T414', 'SG') returning id into v;
  insert into fx values ('store', v);
  insert into public.payment_methods(name) values ('T414 Cash') returning id into v;
  insert into fx values ('cash', v);
  insert into public.customers(full_name, phone) values ('T414 Buyer', '+6591414010') returning id into v;
  insert into fx values ('buyer', v);
  foreach k in array array['a1','a2','a3','a4'] loop
    n := n + 1;
    insert into public.customers(full_name, phone) values ('T414 Affiliate ' || upper(k), '+65914140' || lpad((10 + n)::text, 2, '0'))
      returning id into v;
    insert into fx values (k, v);
    insert into public.customer_affiliates(customer_id, store_id, status, activated_at)
      values (v, pg_temp.fx('store'), 'active', now());
  end loop;
  insert into public.affiliate_accounts(auth_user_id, customer_id, status) values
    (pg_temp.fx('a1_login'), pg_temp.fx('a1'), 'claimed'), (pg_temp.fx('a2_login'), pg_temp.fx('a2'), 'claimed');
  foreach k in array array['i1','i2','i3','i4','i5','i6','i7','i8','i9','i10','i11'] loop
    insert into public.invoices(invoice_no, store_id, customer_id, created_by, status)
      values ('T414-' || upper(k), pg_temp.fx('store'), pg_temp.fx('buyer'), pg_temp.fx('owner'), 'paid')
      returning id into v;
    insert into fx values (k, v);
  end loop;

  -- a1: production's case. September: 1705.59 earned; 1276.30 paid out
  -- (991.64 and 284.66), and later the 991.64 taken back, dated in
  -- September as the four rows of 3 Oct 2026 are. October: 100.80 earned,
  -- 93.72 paid out.
  insert into fx values ('a1_c1', pg_temp.commission('a1', 'i1', 991.64, '2026-09-02'));
  perform pg_temp.commission('a1', 'i2', 284.66, '2026-09-03');
  perform pg_temp.commission('a1', 'i3', 429.29, '2026-09-20');
  perform pg_temp.pay('a1', '2026-09-01', 1276.30);
  perform pg_temp.commission('a1', 'i4', 93.72, '2026-10-02');
  perform pg_temp.commission('a1', 'i5', 7.08, '2026-10-05');
  perform pg_temp.pay('a1', '2026-10-01', 93.72);
  perform pg_temp.takeback('a1', 'i1', 'a1_c1', -991.64, '2026-09-02');

  -- a2: August 100 paid out, all taken back: 100 owed back.
  insert into fx values ('a2_c', pg_temp.commission('a2', 'i6', 100, '2026-08-05'));
  perform pg_temp.pay('a2', '2026-08-01', 100);
  insert into fx values ('a2_t', pg_temp.takeback('a2', 'i6', 'a2_c', -100, '2026-08-05'));

  -- a3: August 50 earned, nothing paid: owed 50, owes nothing back.
  perform pg_temp.commission('a3', 'i7', 50, '2026-08-06');

  -- a4: July 80 paid out, all taken back: 80 owed back.
  insert into fx values ('a4_c', pg_temp.commission('a4', 'i8', 80, '2026-07-05'));
  perform pg_temp.pay('a4', '2026-07-01', 80);
  insert into fx values ('a4_t', pg_temp.takeback('a4', 'i8', 'a4_c', -80, '2026-07-05'));
end $$;

-- ===== 1. Before 414: the deduction, and no way to say it was settled =====
do $$
declare v jsonb;
begin
  if to_regclass('public.affiliate_deduction_settlements') is not null then
    raise notice 'SKIP  section 1: this database already has 414'; return; end if;
  v := pg_temp.figures('a1', true);
  insert into snap values ('before414', v);
  perform pg_temp.check((v->'netted'->>'owed')::numeric = -555.27 and (v->'netted'->>'deduction')::numeric = 555.27
                        and (v->'netted'->>'payable')::numeric = 0,
    '1: the fixture is production''s case: S$555.27 owed back, nothing payable');
  perform pg_temp.check((select jsonb_agg(jsonb_build_object('month', m->>'month', 'earned', (m->>'earned')::numeric,
                                                             'adjustments', (m->>'adjustments')::numeric, 'paid', (m->>'paid')::numeric,
                                                             'balance', (m->>'balance')::numeric) order by m->>'month')
                           from jsonb_array_elements(v->'months') m)
                        = '[{"month": "2026-09-01", "earned": 1705.59, "adjustments": -991.64, "paid": 1276.30, "balance": -562.35},
                            {"month": "2026-10-01", "earned": 100.80, "adjustments": 0, "paid": 93.72, "balance": 7.08}]'::jsonb,
    '1: September -562.35, October +7.08: ' || (v->'months')::text);
  perform pg_temp.check(to_regprocedure('public.record_affiliate_deduction_settlement(uuid,numeric,date,text,text,uuid)') is null,
    '1: there is no way to record that it was settled (the gap)');
end $$;

-- ===== 2. Apply 414; a re-run changes nothing =====
\ir ../../../supabase/414_affiliate_deduction_settlements.sql
create temp table t414_after as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5,
         coalesce(array_to_string(p.proacl, ','), '') as acl
    from pg_proc p where p.pronamespace = 'public'::regnamespace;
create temp table t414_table_after as
  select coalesce(c.relacl::text, '') acl, c.relrowsecurity rls from pg_class c where c.oid = 'public.affiliate_deduction_settlements'::regclass;
\ir ../../../supabase/414_affiliate_deduction_settlements.sql
-- Another version of a function it changes, of one it relies on, and part of
-- it missing: each run refuses, naming it (psql prints the refusals as ERROR
-- lines; they are expected and checked below).
savepoint t414_guard;
create or replace function public.affiliate_portal_earnings() returns jsonb language sql stable security definer
  set search_path = public as $f$ select '{}'::jsonb $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/414_affiliate_deduction_settlements.sql
\set ON_ERROR_STOP on
rollback to savepoint t414_guard;
release savepoint t414_guard;
select set_config('t414.refused_changed', :'LAST_ERROR_MESSAGE', true) as t414_kept \gset
savepoint t414_guard2;
create or replace function public.affiliate_payout_lock() returns void language sql security definer
  set search_path = public as $f$ select null::void $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/414_affiliate_deduction_settlements.sql
\set ON_ERROR_STOP on
rollback to savepoint t414_guard2;
release savepoint t414_guard2;
select set_config('t414.refused_relied', :'LAST_ERROR_MESSAGE', true) as t414_kept \gset
savepoint t414_guard3;
drop function public.void_affiliate_deduction_settlement(uuid, text, uuid);
\set ON_ERROR_STOP off
\ir ../../../supabase/414_affiliate_deduction_settlements.sql
\set ON_ERROR_STOP on
rollback to savepoint t414_guard3;
release savepoint t414_guard3;
select set_config('t414.refused_part', :'LAST_ERROR_MESSAGE', true) as t414_kept \gset
do $$
declare v jsonb;
begin
  perform pg_temp.check(current_setting('t414.refused_changed') like '414: public.affiliate_portal_earnings() is not the version this was tested against%',
    '2: a changed function at another version refuses: ' || current_setting('t414.refused_changed'));
  perform pg_temp.check(current_setting('t414.refused_relied') like '414: public.affiliate_payout_lock() is missing or not the version read on 9 Oct 2026%',
    '2: a relied-on function at another version refuses: ' || current_setting('t414.refused_relied'));
  perform pg_temp.check(current_setting('t414.refused_part') like '414: only part of this migration is installed (4 of 5 new functions%',
    '2: part of it missing refuses: ' || current_setting('t414.refused_part'));
  perform pg_temp.check(not exists (
      select fn, md5, acl from t414_after
      except select p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid)), coalesce(array_to_string(p.proacl, ','), '')
               from pg_proc p where p.pronamespace = 'public'::regnamespace)
    and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace) = (select count(*) from t414_after)
    and (select acl || rls::text from t414_table_after)
        = (select coalesce(c.relacl::text, '') || c.relrowsecurity::text from pg_class c where c.oid = 'public.affiliate_deduction_settlements'::regclass),
    '2: a second run of 414 changes no function, grant or table rule');
  perform pg_temp.check((select count(*) from public.affiliate_deduction_settlements) = 0
                        and not exists (select 1 from public.customers where full_name = '414 check affiliate')
                        and not exists (select 1 from public.profiles where full_name = '414 check')
                        and not exists (select 1 from public.audit_logs where table_name = 'affiliate_deduction_settlements'),
    '2: the migration''s own check left no row');
  for v in select to_jsonb(x) from (values
      ('affiliate_month_balances()', '84c0741e983c8f483d677353c732d891'),
      ('report_affiliates()', '84aa4032d794ecdd58e1ec4ae9b9adbc'),
      ('affiliate_payout_overview()', '2da2a55dade2e16282c03ec3fc3b221d'),
      ('affiliate_portal_earnings()', 'adc91a9be47aff2d0c1bc60eb4834cef'),
      ('referrer_earnings(uuid)', 'f5fe44e5f1ffb14d895721698d6ad212'),
      ('dashboard_summary()', 'd29c77f8ce2fda5e81b134bdced16dcc'),
      ('affiliate_payout_save(uuid,integer,uuid,date,numeric,uuid,date,text,text,text,uuid)', 'dd2993318ffef5c8f60b1e8513ed1902'),
      ('affiliate_deduction_settlement_record(uuid,numeric,date,text,text,uuid,uuid)', 'e0c89b33a3bb8e7d79cf6ccf67fd1e2b'),
      ('affiliate_deduction_settlement_void(uuid,text,uuid,uuid)', 'b5d0a22532b8ab71677825643714734f'),
      ('record_affiliate_deduction_settlement(uuid,numeric,date,text,text,uuid)', '70976b9267b703dc4899b518f46f7ec9'),
      ('void_affiliate_deduction_settlement(uuid,text,uuid)', '6be0c40f6fbe4d6910e1fe749f733c0e'),
      ('trg_affiliate_deduction_settlement_guard()', '2d0f81e74105134faea2d26842f45a6b')) x(fn, md5)
  loop
    perform pg_temp.check(md5(pg_get_functiondef(to_regprocedure('public.' || (v->>'fn')))) = v->>'md5',
      '2: ' || (v->>'fn') || ' is 414''s version');
  end loop;
  -- Grants: the four internals are nobody's but the service role's; the
  -- page's two are signed-in logins' (the function checks who), never anon's.
  perform pg_temp.check(bool_and(not has_function_privilege('anon', to_regprocedure('public.' || f), 'execute')
                                 and not has_function_privilege('authenticated', to_regprocedure('public.' || f), 'execute')
                                 and has_function_privilege('service_role', to_regprocedure('public.' || f), 'execute')),
    '2: the internal functions, affiliate_month_balances and affiliate_payout_save are the service role''s alone')
    from unnest(array['affiliate_deduction_settlement_record(uuid,numeric,date,text,text,uuid,uuid)',
                      'affiliate_deduction_settlement_void(uuid,text,uuid,uuid)',
                      'trg_affiliate_deduction_settlement_guard()', 'affiliate_month_balances()',
                      'affiliate_payout_save(uuid,integer,uuid,date,numeric,uuid,date,text,text,text,uuid)']) f;
  perform pg_temp.check(bool_and(not has_function_privilege('anon', to_regprocedure('public.' || f), 'execute')
                                 and has_function_privilege('authenticated', to_regprocedure('public.' || f), 'execute')),
    '2: Mark as settled, Void and the Reports rows are signed-in logins'', not the anon key''s')
    from unnest(array['record_affiliate_deduction_settlement(uuid,numeric,date,text,text,uuid)',
                      'void_affiliate_deduction_settlement(uuid,text,uuid)', 'report_affiliates()']) f;
  perform pg_temp.check(not has_table_privilege('anon', 'public.affiliate_deduction_settlements', 'select,insert,update,delete,truncate,references,trigger')
    and not has_table_privilege('authenticated', 'public.affiliate_deduction_settlements', 'select,insert,update,delete,truncate,references,trigger')
    and has_table_privilege('service_role', 'public.affiliate_deduction_settlements', 'select')
    and not has_table_privilege('service_role', 'public.affiliate_deduction_settlements', 'insert,update,delete,truncate')
    and (select relrowsecurity from pg_class where oid = 'public.affiliate_deduction_settlements'::regclass)
    and not exists (select 1 from pg_policies where tablename = 'affiliate_deduction_settlements'),
    '2: the table: no client role may touch it, the service role may read it, row level security on with no rule');

  -- With no settlement every figure is as before 414.
  v := pg_temp.figures('a1', true);
  if exists (select 1 from snap where k = 'before414') then
    perform pg_temp.check(v = (select s.v from snap s where s.k = 'before414'),
      '2: with no settlement every page''s figures are exactly as before 414');
  end if;
  insert into snap values ('before', pg_temp.figures('a1', false));
  v := (select s.v from snap s where s.k = 'before');
  perform pg_temp.check((v->'netted'->>'deduction')::numeric = 555.27 and (v->'directory'->>'deduction')::numeric = 555.27
                        and (v->'portal'->>'deduction')::numeric = 555.27 and (v->'portal'->>'settled')::numeric = 0
                        and (v->'reports'->>'settled')::numeric = 0 and (v->'referrer_detail'->'lifetime'->>'settled')::numeric = 0
                        and (select bool_and((m->>'settled')::numeric = 0) from jsonb_array_elements(v->'months') m),
    '2: every page shows the S$555.27 owed back, nothing settled');
end $$;

-- ===== 3. Who may mark it as settled, and what is refused =====
do $$
declare e text; k text; r record;
begin
  foreach k in array array['staff', 'admin', 'inactive', 'nostaff', 'a1_login'] loop
    e := pg_temp.call_as(k, pg_temp.settle_sql('a1', 555.27, '2026-10-09', 'paid_outside_app', 'T414 note', gen_random_uuid()));
    perform pg_temp.check(split_part(e, chr(9), 1) = '42501', '3: ' || k || ' is refused with 42501: ' || e);
    e := pg_temp.call_as(k, format('select public.void_affiliate_deduction_settlement(%L, %L, %L)::text', gen_random_uuid(), 'T414', gen_random_uuid()));
    perform pg_temp.check(split_part(e, chr(9), 1) = '42501', '3: ' || k || ' may not void either: ' || e);
  end loop;
  e := pg_temp.call_as('anon', pg_temp.settle_sql('a1', 555.27, '2026-10-09', 'paid_outside_app', 'T414 note', gen_random_uuid()));
  perform pg_temp.check(split_part(e, chr(9), 1) = '42501', '3: the anon key is refused with 42501: ' || e);
  e := pg_temp.call_as('server', pg_temp.settle_sql('a1', 555.27, '2026-10-09', 'paid_outside_app', 'T414 note', gen_random_uuid()));
  perform pg_temp.check(e like '42501' || chr(9) || 'Sign in as an Owner or Manager%',
    '3: with no signed-in Owner or Manager it is refused (who did it is always recorded): ' || e);
  for r in select * from (values
      (555.28::numeric, '2026-10-09'::date, 'paid_outside_app', 'T414 note', 'S$555.28 is more than the S$555.27 this affiliate owes back. Enter at most S$555.27.'),
      (0, '2026-10-09', 'paid_outside_app', 'T414 note', 'Enter an amount above S$0.00 with at most two decimal places.'),
      (-1, '2026-10-09', 'paid_outside_app', 'T414 note', 'Enter an amount above S$0.00 with at most two decimal places.'),
      (1.005, '2026-10-09', 'paid_outside_app', 'T414 note', 'Enter an amount above S$0.00 with at most two decimal places.'),
      (null, '2026-10-09', 'paid_outside_app', 'T414 note', 'Enter an amount above S$0.00 with at most two decimal places.'),
      (10, public.sg_today() + 1, 'paid_outside_app', 'T414 note', 'Enter the date it was settled. It cannot be after today in Singapore.'),
      (10, null, 'paid_outside_app', 'T414 note', 'Enter the date it was settled. It cannot be after today in Singapore.'),
      (10, '2019-12-31', 'paid_outside_app', 'T414 note', 'Enter the date it was settled. It cannot be before 1 Jan 2020.'),
      (10, '2026-10-01', 'paid_outside_app', 'T414 note', 'The date it was settled cannot be before the first payout to this affiliate, on 2 Oct 2026.'),
      (10, '2026-10-09', 'refunded', 'T414 note', 'Choose how it was settled: paid back to us, written off, or paid off outside the app.'),
      (10, '2026-10-09', 'paid_back', '   ', 'A note is required: say how and why it was settled.'),
      (10, '2026-10-09', 'paid_back', null, 'A note is required: say how and why it was settled.'),
      (10, '2026-10-09', 'paid_back', repeat('x', 2001), 'The note is too long (2,000 characters at most).')
    ) x(amount, on_day, method, note, msg)
  loop
    foreach k in array array['owner', 'manager'] loop
      e := pg_temp.call_as(k, pg_temp.settle_sql('a1', r.amount, r.on_day, r.method, r.note, gen_random_uuid()));
      perform pg_temp.check(e = 'P0001' || chr(9) || r.msg, format('3: %s, %s on %s (%s): refused: %s', k, r.amount, r.on_day, r.method, e));
    end loop;
  end loop;
  e := pg_temp.call_as('owner', pg_temp.settle_sql('a3', 10, '2026-10-09', 'written_off', 'T414 note', gen_random_uuid()));
  perform pg_temp.check(e = 'P0001' || chr(9) || 'This affiliate owes nothing back, so there is nothing to settle. Refresh the summary.',
    '3: an affiliate who owes nothing back cannot be settled: ' || e);
  e := pg_temp.call_as('owner', format('select public.record_affiliate_deduction_settlement(%L, 10, %L, %L, %L, %L)::text',
         gen_random_uuid(), '2026-10-09', 'written_off', 'T414 note', gen_random_uuid()));
  perform pg_temp.check(e = 'P0001' || chr(9) || 'Affiliate not found.', '3: an unknown affiliate: ' || e);
  e := pg_temp.call_as('owner', pg_temp.settle_sql('a1', 10, '2026-10-09', 'written_off', 'T414 note', null));
  perform pg_temp.check(e like 'P0001' || chr(9) || 'A request identifier is required%', '3: no request id: ' || e);
  perform pg_temp.check((select count(*) from public.affiliate_deduction_settlements) = 0
                        and (select s.v from snap s where s.k = 'before') = pg_temp.figures('a1', false),
    '3: nothing refused was written, and no figure moved');
end $$;

-- ===== 4. The Owner marks the S$555.27 as settled: every page follows =====
do $$
declare v jsonb; b jsonb := (select s.v from snap s where s.k = 'before'); res jsonb; e text; ov jsonb; st jsonb;
begin
  res := pg_temp.ok_as('owner', pg_temp.settle_sql('a1', 555.27, '2026-10-09', 'paid_outside_app',
                         '  Settled outside the app (T414).  ', '00000000-0000-4000-8000-000000000001'));
  insert into fx values ('s1', (res->>'id')::uuid);
  perform pg_temp.check(res - 'id' = jsonb_build_object('referrer', pg_temp.fx('a1'), 'amount', 555.27,
                                                        'settled_on', '2026-10-09', 'method', 'paid_outside_app'),
    '4: Mark as settled answers what it recorded: ' || res::text);
  perform pg_temp.check((select s.amount = 555.27 and s.settled_on = '2026-10-09' and s.method = 'paid_outside_app'
                                and s.note = 'Settled outside the app (T414).' and s.created_by = pg_temp.fx('owner')
                                and s.voided_at is null and s.referrer_customer_id = pg_temp.fx('a1')
                           from public.affiliate_deduction_settlements s where s.id = pg_temp.fx('s1')),
    '4: one dated record: amount, date, how, the note (trimmed), who recorded it');
  v := pg_temp.figures('a1', false);
  insert into snap values ('settled', v);
  perform pg_temp.check(v->'netted' = jsonb_build_object('referrer', pg_temp.fx('a1'), 'owed', 0.00, 'unpaid', 0.00, 'deduction', 0.00, 'payable', 0.00),
    '4: the affiliate owes nothing and is owed nothing: ' || (v->'netted')::text);
  perform pg_temp.check((select jsonb_agg(jsonb_build_object('month', m->>'month', 'balance', (m->>'balance')::numeric,
                                                             'settled', (m->>'settled')::numeric, 'review', m->'review_reason'))
                           from jsonb_array_elements(v->'months') m)
                        = '[{"month": "2026-09-01", "balance": -7.08, "settled": 555.27, "review": null},
                            {"month": "2026-10-01", "balance": 7.08, "settled": 0, "review": null}]'::jsonb,
    '4: September takes the settlement (-562.35 + 555.27 = -7.08); October''s 7.08 stays counted against it: ' || (v->'months')::text);
  perform pg_temp.check((select bool_and((g->>'payable')::numeric = 0 and (g->>'referrer_deduction')::numeric = 0
                                         and (g->>'referrer_owed')::numeric = 0)
                           from jsonb_array_elements(v->'overview_months') g)
                        and (v->'overview_affiliate'->>'deduction')::numeric = 0,
    '4: the payout panel: nothing payable and no "Affiliate owes ... back" line');
  perform pg_temp.check((v->'directory'->>'unpaid')::numeric = 0 and (v->'directory'->>'deduction')::numeric = 0,
    '4: the Affiliates page: Unpaid S$0.00, no "Owes ... back"');
  perform pg_temp.check((v->>'referrers_tab')::numeric = 0 and (v->>'staff_directory')::numeric = 0,
    '4: the Referrers tab and the staff directory: 0');
  perform pg_temp.check((v->'referrer_detail'->'lifetime'->>'total_earned')::numeric = 0
                        and (v->'referrer_detail'->'lifetime'->>'settled')::numeric = 555.27
                        and (select (m->>'settled')::numeric = 555.27 and (m->>'unpaid')::numeric = -7.08
                               from jsonb_array_elements(v->'referrer_detail'->'monthly') m where m->>'month' = '2026-09'),
    '4: the Referrers detail: Unpaid total 0, S$555.27 settled, against September');
  perform pg_temp.check((v->'referrer_detail'->'lifetime'->>'tier1_earned')::numeric + (v->'referrer_detail'->'lifetime'->>'tier2_earned')::numeric
                          + (v->'referrer_detail'->'lifetime'->>'settled')::numeric
                        = (v->'referrer_detail'->'lifetime'->>'total_earned')::numeric
                        and (v->'referrer_detail'->'lifetime'->>'tier1_earned')::numeric + (v->'referrer_detail'->'lifetime'->>'tier2_earned')::numeric = -555.27
                        and (b->'referrer_detail'->'lifetime'->>'tier1_earned')::numeric + (b->'referrer_detail'->'lifetime'->>'tier2_earned')::numeric
                          = (b->'referrer_detail'->'lifetime'->>'total_earned')::numeric,
    '4: the Referrers detail''s tier boxes (not yet in a payout) + settled = Unpaid total, before and after: '
      || (v->'referrer_detail'->'lifetime')::text);
  perform pg_temp.check((v->'reports'->>'settled')::numeric = 555.27 and (v->'reports'->>'paid')::numeric = 1370.02
                        and (v->'reports'->>'earned')::numeric = 814.75
                        and (v->'reports'->>'earned')::numeric - (v->'reports'->>'paid')::numeric + (v->'reports'->>'settled')::numeric = 0,
    '4: the Reports rows: earned 814.75 - paid out 1370.02 + settled 555.27 = Outstanding 0, nothing to recover');
  perform pg_temp.check((v->'portal'->>'unpaid')::numeric = 0 and (v->'portal'->>'deduction')::numeric = 0
                        and (v->'portal'->>'settled')::numeric = 555.27 and (v->'portal'->>'lifetime')::numeric = 814.75
                        and (v->'portal'->>'paid')::numeric = 1370.02
                        and (v->'portal_dashboard'->>'deduction')::numeric = 0 and (v->'portal_dashboard'->>'settled')::numeric = 555.27,
    '4: the affiliate''s portal: Unpaid 0, no deduction, S$555.27 settled; lifetime and paid as before');
  perform pg_temp.check((v->'dashboard'->>'unpaid_commission')::numeric = (b->'dashboard'->>'unpaid_commission')::numeric
                        and (b->'dashboard'->>'commission_deductions')::numeric - (v->'dashboard'->>'commission_deductions')::numeric = 555.27,
    '4: the Dashboard: unpaid commission unchanged, S$555.27 less to recover');
  perform pg_temp.check((v->'dashboard'->>'unpaid_commission')::numeric = (select sum(unpaid) from public.affiliate_referrer_balances())
                        and (v->'dashboard'->>'commission_deductions')::numeric = (select sum(deduction) from public.affiliate_referrer_balances()),
    '4: the Dashboard''s figures are the Commissions page''s, added up');
  -- The payout panel lists it with how, the note and who recorded it.
  ov := pg_temp.ok_as('admin', 'select public.affiliate_payout_overview()::text');
  st := (select s from jsonb_array_elements(ov->'settlements') s where s->>'id' = pg_temp.fx('s1')::text);
  perform pg_temp.check(st->>'method' = 'paid_outside_app' and st->>'note' = 'Settled outside the app (T414).'
                        and st->>'created_by_name' = 'T414 Owner' and st->'voided_at' = 'null'::jsonb
                        and (st->>'amount')::numeric = 555.27 and st->>'settled_on' = '2026-10-09'
                        and not st ? 'request_id' and not st ? 'void_request_id',
    '4: the payout history lists the settlement (an Admin reads it too): ' || coalesce(st::text, 'missing'));
  -- Payouts: still nothing payable.
  e := pg_temp.call_as('owner', format('select public.record_affiliate_payout(%L, %L, 7.08, %L, %L, null, null, %L)::text',
         pg_temp.fx('a1'), '2026-10-01', pg_temp.fx('cash'), '2026-10-09', gen_random_uuid()));
  perform pg_temp.check(e like 'P0001' || chr(9) || 'Amount exceeds what this affiliate can be paid now once all their months are counted, S$0.00.%',
    '4: October''s 7.08 is still not paid (it is counted against the debt): ' || e);
  -- No commission row, take-back or payout was touched.
  perform pg_temp.check((select count(*) from public.commissions where referrer_customer_id = pg_temp.fx('a1')) = 6
                        and (select sum(commission_amount) from public.commissions where referrer_customer_id = pg_temp.fx('a1')) = 814.75
                        and (select count(*) || '/' || sum(total_amount) from public.commission_payouts where referrer_customer_id = pg_temp.fx('a1')) = '2/1370.02',
    '4: the commission rows, the take-back and the payouts are as they were');
end $$;

-- ===== 5. A retry gives the first answer; a second click is refused =====
do $$
declare e text; res jsonb;
begin
  res := pg_temp.ok_as('owner', pg_temp.settle_sql('a1', 555.27, '2026-10-09', 'paid_outside_app',
                         'Settled outside the app (T414).', '00000000-0000-4000-8000-000000000001'));
  perform pg_temp.check(res->>'id' = pg_temp.fx('s1')::text and (select count(*) from public.affiliate_deduction_settlements) = 1,
    '5: the same request again (a lost answer, retried) gives the same settlement, recorded once');
  e := pg_temp.call_as('manager', pg_temp.settle_sql('a1', 555.27, '2026-10-09', 'paid_outside_app',
                         'Settled outside the app (T414).', '00000000-0000-4000-8000-000000000001'));
  perform pg_temp.check(e like 'P0001' || chr(9) || 'This request identifier was already used with different details.%',
    '5: the same request id by someone else is refused: ' || e);
  e := pg_temp.call_as('owner', pg_temp.settle_sql('a1', 500, '2026-10-09', 'paid_outside_app',
                         'Settled outside the app (T414).', '00000000-0000-4000-8000-000000000001'));
  perform pg_temp.check(e like 'P0001' || chr(9) || 'This request identifier was already used with different details.%',
    '5: the same request id with another amount is refused: ' || e);
  e := pg_temp.call_as('manager', pg_temp.settle_sql('a1', 555.27, '2026-10-09', 'paid_outside_app', 'T414 second click', gen_random_uuid()));
  perform pg_temp.check(e = 'P0001' || chr(9) || 'This affiliate owes nothing back, so there is nothing to settle. Refresh the summary.',
    '5: a second click (another request) finds nothing owed back: ' || e);
  perform pg_temp.check((select count(*) from public.affiliate_deduction_settlements) = 1, '5: still one settlement');
end $$;

-- ===== 6. A void puts every figure back; a void is final and audited =====
do $$
declare e text; res jsonb; v jsonb; b jsonb := (select s.v from snap s where s.k = 'before');
begin
  e := pg_temp.call_as('owner', format('select public.void_affiliate_deduction_settlement(%L, %L, %L)::text', pg_temp.fx('s1'), '   ', gen_random_uuid()));
  perform pg_temp.check(e = 'P0001' || chr(9) || 'A reason is required to void a settlement.', '6: a void needs a reason: ' || e);
  e := pg_temp.call_as('owner', format('select public.void_affiliate_deduction_settlement(%L, %L, %L)::text', gen_random_uuid(), 'T414', gen_random_uuid()));
  perform pg_temp.check(e = 'P0001' || chr(9) || 'Settlement not found. Refresh the payouts.', '6: an unknown settlement: ' || e);
  res := pg_temp.ok_as('manager', format('select public.void_affiliate_deduction_settlement(%L, %L, %L)::text',
           pg_temp.fx('s1'), ' T414: recorded against the wrong affiliate ', '00000000-0000-4000-8000-000000000002'));
  perform pg_temp.check(res = jsonb_build_object('id', pg_temp.fx('s1'), 'referrer', pg_temp.fx('a1'), 'amount', 555.27, 'voided', true),
    '6: a Manager voids it: ' || res::text);
  perform pg_temp.check(pg_temp.ok_as('manager', format('select public.void_affiliate_deduction_settlement(%L, %L, %L)::text',
           pg_temp.fx('s1'), 'T414: recorded against the wrong affiliate', '00000000-0000-4000-8000-000000000002')) = res,
    '6: the same void again (retried) gives the same answer');
  e := pg_temp.call_as('owner', format('select public.void_affiliate_deduction_settlement(%L, %L, %L)::text', pg_temp.fx('s1'), 'T414 again', gen_random_uuid()));
  perform pg_temp.check(e = 'P0001' || chr(9) || 'This settlement was already voided. Refresh the payouts.', '6: voided once only: ' || e);
  perform pg_temp.check((select s.voided_by = pg_temp.fx('manager') and s.void_reason = 'T414: recorded against the wrong affiliate'
                                and s.voided_at is not null and s.amount = 555.27 and s.note = 'Settled outside the app (T414).'
                           from public.affiliate_deduction_settlements s where s.id = pg_temp.fx('s1')),
    '6: the record stays, marked void, with who, when and why');
  v := pg_temp.figures('a1', false);
  perform pg_temp.check(v = b, '6: after the void every page''s figures are exactly as before the settlement');
  perform pg_temp.check((select count(*) from jsonb_array_elements(pg_temp.ok_as('owner', 'select public.affiliate_payout_overview()::text')->'settlements') s
                          where s->>'id' = pg_temp.fx('s1')::text and s->>'voided_by_name' = 'T414 Manager'
                            and s->>'void_reason' = 'T414: recorded against the wrong affiliate') = 1,
    '6: the payout history still lists it, voided, with who and why');
  perform pg_temp.check((select count(*) filter (where al.action = 'affiliate_deduction_settled' and al.changed_by = pg_temp.fx('owner')
                                                       and al.actor_role = 'owner' and al.module = 'commissions'
                                                       and al.reason = 'Settled outside the app (T414).'
                                                       and (al.old_data->>'deduction')::numeric = 555.27
                                                       and (al.new_data->>'deduction_after')::numeric = 0) = 1
                          and count(*) filter (where al.action = 'affiliate_deduction_settlement_voided' and al.changed_by = pg_temp.fx('manager')
                                                 and al.actor_role = 'manager' and al.reason = 'T414: recorded against the wrong affiliate'
                                                 and al.old_data->'voided_at' = 'null'::jsonb and al.new_data->>'voided_at' is not null) = 1
                          and count(*) = 2
                           from public.audit_logs al where al.record_id = pg_temp.fx('s1')),
    '6: one audit row for the settlement and one for the void, each with who and why');
  -- Settled again (the record the Owner wants), for what follows.
  res := pg_temp.ok_as('owner', pg_temp.settle_sql('a1', 555.27, '2026-10-09', 'paid_outside_app', 'Settled outside the app (T414).', gen_random_uuid()));
  insert into fx values ('s1b', (res->>'id')::uuid);
  perform pg_temp.check(pg_temp.figures('a1', false) - 'dashboard' = (select s.v - 'dashboard' from snap s where s.k = 'settled'),
    '6: settled again: every figure as after the first settlement');
end $$;

-- ===== 7. Part of a deduction: settled in two, a void, written off =====
do $$
declare e text; res jsonb;
begin
  res := pg_temp.ok_as('manager', pg_temp.settle_sql('a2', 60, '2026-10-01', 'paid_back', 'T414 paid back 60', gen_random_uuid()));
  insert into fx values ('s2', (res->>'id')::uuid);
  perform pg_temp.check((select deduction = 40 and owed = -40 and unpaid = 0 from public.affiliate_referrer_balances() where referrer = pg_temp.fx('a2')),
    '7: S$60.00 paid back of 100: S$40.00 still owed back');
  perform pg_temp.check((pg_temp.ok_as('a2_login', 'select public.affiliate_portal_earnings()::text')->'summary'->>'deduction')::numeric = 40,
    '7: the affiliate sees S$40.00 still to be recovered');
  e := pg_temp.call_as('owner', pg_temp.settle_sql('a2', 40.01, '2026-10-02', 'written_off', 'T414 rest', gen_random_uuid()));
  perform pg_temp.check(e = 'P0001' || chr(9) || 'S$40.01 is more than the S$40.00 this affiliate owes back. Enter at most S$40.00.',
    '7: no more than what is still owed back: ' || e);
  e := pg_temp.call_as('owner', pg_temp.settle_sql('a2', 40, '2026-01-15', 'written_off', 'T414 rest', gen_random_uuid()));
  perform pg_temp.check(e = 'P0001' || chr(9) || 'The date it was settled cannot be before the first payout to this affiliate, on 2 Sep 2026.',
    '7: not dated before the payout that made the deduction (no month with nothing in it takes it): ' || e);
  perform pg_temp.ok_as('owner', pg_temp.settle_sql('a2', 40, '2026-09-02', 'written_off', 'T414 rest written off', gen_random_uuid()));
  perform pg_temp.check((select deduction = 0 and owed = 0 from public.affiliate_referrer_balances() where referrer = pg_temp.fx('a2'))
                        and (select balance = 0 and settled = 100 from public.affiliate_month_balances() where referrer = pg_temp.fx('a2') and month = '2026-08-01'),
    '7: the rest written off: nothing owed either way; August takes both');
  perform pg_temp.ok_as('owner', format('select public.void_affiliate_deduction_settlement(%L, %L, %L)::text', pg_temp.fx('s2'), 'T414 the 60 never arrived', gen_random_uuid()));
  perform pg_temp.check((select deduction = 60 from public.affiliate_referrer_balances() where referrer = pg_temp.fx('a2')),
    '7: the S$60.00 voided: S$60.00 is owed back again');
end $$;

-- ===== 8. Commission earned later is paid as before =====
-- The settlement fills the months owed back; it never makes a month payable,
-- so later commission is offered against the months that hold it.
do $$
declare ov jsonb; g jsonb;
begin
  perform pg_temp.commission('a1', 'i9', 100, '2026-11-05');
  perform pg_temp.check((select owed = 100 and payable = 100 and deduction = 0 from public.affiliate_referrer_balances() where referrer = pg_temp.fx('a1')),
    '8: S$100.00 earned in November: S$100.00 payable');
  ov := pg_temp.ok_as('owner', 'select public.affiliate_payout_overview()::text');
  perform pg_temp.check((select jsonb_object_agg(g2->>'month', (g2->>'payable')::numeric) from jsonb_array_elements(ov->'groups') g2
                          where g2->>'referrer' = pg_temp.fx('a1')::text)
                        = '{"2026-09-01": 0, "2026-10-01": 7.08, "2026-11-01": 92.92}'::jsonb,
    '8: offered oldest first: October 7.08, November 92.92 (each month''s commission)');
  perform pg_temp.pay('a1', '2026-10-01', 7.08);
  perform pg_temp.pay('a1', '2026-11-01', 92.92);
  perform pg_temp.check((select owed = 0 and payable = 0 from public.affiliate_referrer_balances() where referrer = pg_temp.fx('a1'))
                        and not exists (select 1 from public.commission_payouts p where p.referrer_customer_id = pg_temp.fx('a1')
                                         and (p.allocation_state <> 'verified'
                                              or p.total_amount <> (select coalesce(sum(a.amount), 0) from public.commission_payout_allocations a where a.payout_id = p.id))),
    '8: both are recorded and allocated in full; the affiliate is square again');
end $$;

-- ===== 9. Settled beyond what is owed back (a take-back lowered later) =====
-- What the settlements come to beyond what the months now owe back shows in
-- the month of the latest settlement, under review: the page offers no
-- payout there, and the API refuses one (affiliate_payout_save reads the same
-- review), even when the affiliate has commission elsewhere that may be paid.
-- How such money goes back to the affiliate is the Owner's to decide.
do $$
declare m jsonb; e text; ov jsonb;
  c_review constant text := 'Deductions marked as settled come to S$30.00 more than this affiliate now owes back. Review with the Owner before recording a payout for this month.';
begin
  perform pg_temp.ok_as('owner', pg_temp.settle_sql('a4', 80, '2026-10-03', 'paid_back', 'T414 a4 paid back', gen_random_uuid()));
  perform pg_temp.check((select owed = 0 from public.affiliate_referrer_balances() where referrer = pg_temp.fx('a4')),
    '9: a4''s S$80.00 paid back');
  update public.commissions set commission_amount = -50, line_amount = -500 where id = pg_temp.fx('a4_t');
  select jsonb_agg(jsonb_build_object('month', b.month, 'balance', b.balance, 'settled', b.settled, 'review', b.review_reason) order by b.month)
    into m from public.affiliate_month_balances() b where b.referrer = pg_temp.fx('a4');
  perform pg_temp.check(m = jsonb_build_array(
      jsonb_build_object('month', '2026-07-01', 'balance', 0, 'settled', 50, 'review', null),
      jsonb_build_object('month', '2026-10-01', 'balance', 30, 'settled', 30, 'review', c_review)),
    '9: the take-back lowered to 50: July takes 50, the 30 beyond it shows in October under review: ' || m::text);
  perform pg_temp.check((select owed = 30 and unpaid = 30 and payable = 0 from public.affiliate_referrer_balances() where referrer = pg_temp.fx('a4')),
    '9: owed S$30.00, but none of it offered as payable');
  e := pg_temp.call_as('owner', format('select public.record_affiliate_payout(%L, %L, 30, %L, %L, null, null, %L)::text',
         pg_temp.fx('a4'), '2026-10-01', pg_temp.fx('cash'), '2026-10-09', gen_random_uuid()));
  perform pg_temp.check(e = 'P0001' || chr(9) || c_review, '9: and a payout against it is refused, with the review: ' || e);

  -- Commission in that month and in a later one: the later one is paid as
  -- usual; the month under review is still not, though its commission could
  -- be allocated and the affiliate's payable would cover it.
  perform pg_temp.commission('a4', 'i10', 20, '2026-10-04');
  perform pg_temp.commission('a4', 'i11', 25, '2026-11-05');
  select jsonb_agg(jsonb_build_object('month', b.month, 'balance', b.balance, 'settled', b.settled, 'review', b.review_reason) order by b.month)
    into m from public.affiliate_month_balances() b where b.referrer = pg_temp.fx('a4');
  perform pg_temp.check(m = jsonb_build_array(
      jsonb_build_object('month', '2026-07-01', 'balance', 0, 'settled', 50, 'review', null),
      jsonb_build_object('month', '2026-10-01', 'balance', 50, 'settled', 30, 'review', c_review),
      jsonb_build_object('month', '2026-11-01', 'balance', 25, 'settled', 0, 'review', null))
    and (select owed = 75 and payable = 25 from public.affiliate_referrer_balances() where referrer = pg_temp.fx('a4')),
    '9: October 50 under review, November 25 payable: ' || m::text);
  ov := pg_temp.ok_as('owner', 'select public.affiliate_payout_overview()::text');
  perform pg_temp.check((select jsonb_object_agg(g->>'month', (g->>'payable')::numeric) from jsonb_array_elements(ov->'groups') g
                          where g->>'referrer' = pg_temp.fx('a4')::text)
                        = '{"2026-07-01": 0, "2026-10-01": 0, "2026-11-01": 25}'::jsonb,
    '9: the page offers nothing for October, S$25.00 for November');
  e := pg_temp.call_as('owner', format('select public.record_affiliate_payout(%L, %L, 20, %L, %L, null, null, %L)::text',
         pg_temp.fx('a4'), '2026-10-01', pg_temp.fx('cash'), '2026-10-09', gen_random_uuid()));
  perform pg_temp.check(e = 'P0001' || chr(9) || c_review, '9: a payout for October is refused by the API too: ' || e);
  perform pg_temp.pay('a4', '2026-11-01', 25);
  perform pg_temp.check((select owed = 50 and payable = 0 from public.affiliate_referrer_balances() where referrer = pg_temp.fx('a4'))
                        and (select count(*) from public.commission_payouts where referrer_customer_id = pg_temp.fx('a4')) = 2,
    '9: November is paid; nothing was paid for October');
end $$;

-- ===== 10. Never deleted, never rewritten; it moves with a merged customer =====
do $$
declare e text;
begin
  begin
    delete from public.affiliate_deduction_settlements where id = pg_temp.fx('s1');
    e := 'deleted';
  exception when others then e := sqlerrm; end;
  perform pg_temp.check(e = 'A deduction settlement is never deleted. Void it instead, with a reason.', '10: not deleted, even by the database owner: ' || e);
  begin
    update public.affiliate_deduction_settlements set amount = 1 where id = pg_temp.fx('s1b');
    e := 'changed';
  exception when others then e := sqlerrm; end;
  perform pg_temp.check(e = 'A deduction settlement is not changed once recorded. Void it, with a reason, and record it again.', '10: not rewritten: ' || e);
  begin
    update public.affiliate_deduction_settlements set voided_at = null, voided_by = null, void_reason = null, void_request_id = null
     where id = pg_temp.fx('s1');
    e := 'unvoided';
  exception when others then e := sqlerrm; end;
  perform pg_temp.check(e = 'A voided deduction settlement stays voided.', '10: a void is final: ' || e);
  update public.affiliate_deduction_settlements set referrer_customer_id = pg_temp.fx('a3') where id = pg_temp.fx('s2');
  perform pg_temp.check((select referrer_customer_id from public.affiliate_deduction_settlements where id = pg_temp.fx('s2')) = pg_temp.fx('a3'),
    '10: the affiliate it belongs to may change (a customer merge moves it with the person)');
end $$;

-- ===== 11. The portal never shows the note, how, or who =====
do $$
declare v text;
begin
  v := pg_temp.call_as('a1_login', 'select public.affiliate_portal_earnings()::text || public.affiliate_portal_dashboard()::text || public.affiliate_portal_payouts()::text || public.affiliate_portal_purchases()::text');
  perform pg_temp.check(v like 'ok%' and v not like '%T414)%' and v not like '%outside%' and v not like '%paid_back%'
                        and v not like '%written%' and v not like '%T414 Owner%' and v not like '%' || pg_temp.fx('s1b')::text || '%',
    '11: the affiliate''s pages carry the amount settled only');
  v := pg_temp.call_as('a1_login', format('select count(*)::text from public.affiliate_deduction_settlements'));
  perform pg_temp.check(split_part(v, chr(9), 1) = '42501', '11: and the affiliate cannot read the table: ' || v);
end $$;

rollback;
