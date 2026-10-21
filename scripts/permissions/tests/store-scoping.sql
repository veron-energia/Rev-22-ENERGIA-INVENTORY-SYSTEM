-- An invoice's lines follow the invoice's store (430, X-10).
--
-- invoices, invoice_payments, hand-overs and the other invoice tables are read
-- by the people who work at the invoice's store (Owners and Admins at every
-- store). Before 430 five tables of invoice detail were read by any active
-- member of staff, for every store: invoice_items, invoice_revisions,
-- invoice_promotion_selections, invoice_refunds and invoice_credit_splits.
-- This suite shows that with Staff, a Manager and an Inventory Manager who
-- each work at store A only, applies 430, and checks:
--   * each of them reads store A's rows of the five tables, and none of store
--     B's; Staff at both stores and the Owner read both; a pending invitee, a
--     deleted Manager and a login with no profile read none;
--   * the Invoices page's own reads of an invoice (lines by invoice, picks by
--     line, revisions by invoice) still answer for store A, and the detail
--     functions still answer for store A and refuse store B;
--   * nobody signed in may write the five tables (no grant), and the public
--     key may not read them;
--   * current_user_store_ids() and user_has_store_access() for each login;
--   * the five reads are planned with InitPlans, with no helper per row.
--
--   psql -X -v ON_ERROR_STOP=1 -v mig=supabase/430_policies_store_scoped_and_fast.sql \
--        -f scripts/permissions/tests/store-scoping.sql
-- It needs a database with every batch before 430 applied (430 refuses
-- otherwise). Disposable database only; everything is rolled back. Fixture
-- names carry SSX, phones are ACMA's fictional +61 4915 numbers, emails
-- @example.com.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';

create temp table ssx(k text primary key, id uuid not null);
create function pg_temp.ssx_id(p text) returns uuid language sql stable as $f$ select id from ssx where k = p $f$;
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$f$ begin if ok is distinct from true then raise exception 'FAIL: %', msg; end if; raise notice 'PASS  %', msg; end $f$;

-- Run p_sql as a login, roll it back, and return 'ok', a tab and its answer,
-- or the SQLSTATE. p_who: a login key or 'anon'.
create function pg_temp.ssx_try(p_who text, p_sql text) returns text language plpgsql as $f$
declare v_out text; v_state text; v_msg text;
begin
  begin
    if p_who = 'anon' then
      perform set_config('request.jwt.claims', '{"role":"anon"}', true);
      execute 'set local role anon';
    else
      perform set_config('request.jwt.claims',
        json_build_object('sub', pg_temp.ssx_id(p_who), 'role', 'authenticated')::text, true);
      execute 'set local role authenticated';
    end if;
    execute p_sql into v_out;
    raise exception using errcode = 'SSX01', message = coalesce(v_out, '');
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    if v_state = 'SSX01' then return 'ok' || chr(9) || v_msg; end if;
    return v_state;
  end;
end $f$;

-- ── Fixture (as the server; triggers and foreign keys off while it is written) ──
do $$
declare k text; v uuid; st_a uuid; st_b uuid; prod uuid; c1 uuid; c2 uuid; pm uuid; inv uuid; it uuid; s text;
begin
  perform set_config('request.jwt.claims', '', true);
  set local session_replication_role = replica;
  foreach k in array array['owner', 'mgr_a', 'im_a', 'staff_a', 'staff_ab', 'pending', 'deleted', 'nostaff'] loop
    insert into auth.users(id, email) values (gen_random_uuid(), 'ssx-' || replace(k, '_', '-') || '@example.com') returning id into v;
    insert into ssx values (k, v);
  end loop;
  insert into public.profiles(id, full_name, email, role, is_active, invitation_status, deleted_at, created_at, updated_at)
  select s2.id, 'SSX ' || s2.k, 'ssx-' || replace(s2.k, '_', '-') || '@example.com', x.role::public.user_role, true, x.inv,
         case when s2.k = 'deleted' then now() end, now(), now()
    from ssx s2 join (values ('owner', 'owner', null), ('mgr_a', 'manager', null), ('im_a', 'inventory_manager', null),
                             ('staff_a', 'staff', null), ('staff_ab', 'staff', 'accepted'), ('pending', 'staff', 'pending'),
                             ('deleted', 'manager', null)) x(k, role, inv) on x.k = s2.k;
  insert into public.stores(name, code, country_code) values ('SSX Store A', 'SSXA', 'SG') returning id into st_a;
  insert into public.stores(name, code, country_code) values ('SSX Store B', 'SSXB', 'SG') returning id into st_b;
  insert into ssx values ('store_a', st_a), ('store_b', st_b);
  insert into public.user_store_assignments(user_id, store_id)
  select pg_temp.ssx_id(x.k), x.st
    from (values ('mgr_a', st_a), ('im_a', st_a), ('staff_a', st_a), ('staff_ab', st_a), ('staff_ab', st_b),
                 ('pending', st_a), ('deleted', st_a)) x(k, st);
  insert into public.products(name, sku) values ('SSX Product', 'SSX-1') returning id into prod;
  insert into public.payment_methods(name) values ('SSX Cash') returning id into pm;
  insert into public.customers(full_name, phone, email) values ('SSX Customer A', '+61491571266', 'ssx-a@example.com') returning id into c1;
  insert into public.customers(full_name, phone, email) values ('SSX Customer B', '+61491571491', 'ssx-b@example.com') returning id into c2;
  foreach s in array array['a', 'b'] loop
    insert into public.invoices(invoice_no, store_id, customer_id, created_by, status, subtotal, total_amount, business_date)
      values ('SSX-INV-' || upper(s), case s when 'a' then st_a else st_b end, case s when 'a' then c1 else c2 end,
              pg_temp.ssx_id('owner'), 'paid', 10, 10, current_date) returning id into inv;
    insert into public.invoice_items(invoice_id, product_id, line_kind, quantity, unit_price, line_total)
      values (inv, prod, 'product', 1, 10, 10) returning id into it;
    insert into public.invoice_revisions(invoice_id, revision_no, snapshot) values (inv, 1, '{}');
    insert into public.invoice_promotion_selections(invoice_item_id, product_id, quantity) values (it, prod, 1);
    insert into public.invoice_refunds(invoice_id, amount) values (inv, 1);
    insert into public.invoice_credit_splits(invoice_id, invoice_item_id, customer_id, amount)
      values (inv, it, case s when 'a' then c1 else c2 end, 1);
    insert into public.invoice_payments(invoice_id, payment_method_id, amount, received_by)
      values (inv, pm, 10, pg_temp.ssx_id('owner'));
    insert into ssx values ('inv_' || s, inv), ('item_' || s, it);
  end loop;
  set local session_replication_role = origin;
end $$;

-- ── 1. Before 430 ────────────────────────────────────────────────────────────
do $$
declare t text;
begin
  foreach t in array array['invoice_items', 'invoice_revisions', 'invoice_promotion_selections', 'invoice_refunds', 'invoice_credit_splits'] loop
    perform pg_temp.check(pg_temp.ssx_try('staff_a', format('select count(*)::text from public.%I', t)) = 'ok' || chr(9) || '2',
      format('before 430: Staff at store A read both stores'' %s', t));
  end loop;
  perform pg_temp.check(pg_temp.ssx_try('staff_a', 'select count(*)::text from public.invoices where invoice_no like ''SSX-%''') = 'ok' || chr(9) || '1',
    'before 430: but only store A''s invoice');
end $$;

-- ── 2. 430 ───────────────────────────────────────────────────────────────────
\i :mig
reset role;
select set_config('request.jwt.claims', '', true);

-- ── 3. After ─────────────────────────────────────────────────────────────────
do $$
declare
  c_tables constant text[] := array['invoice_items', 'invoice_revisions', 'invoice_promotion_selections',
                                    'invoice_refunds', 'invoice_credit_splits'];
  t text; w text; v text; v_exp text; r record; v_plan text;
  a uuid := pg_temp.ssx_id('store_a'); b uuid := pg_temp.ssx_id('store_b');
begin
  -- The five tables, by store: one row per store's invoice in each.
  foreach t in array c_tables loop
    foreach w in array array['owner', 'mgr_a', 'im_a', 'staff_a', 'staff_ab', 'pending', 'deleted', 'nostaff'] loop
      v := pg_temp.ssx_try(w, format('select count(*)::text from public.%I', t));
      v_exp := case when w in ('owner', 'staff_ab') then '2' when w in ('mgr_a', 'im_a', 'staff_a') then '1' else '0' end;
      perform pg_temp.check(v = 'ok' || chr(9) || v_exp, format('%s reads %s of %s rows (%s)', w, v_exp, t, v));
    end loop;
    -- The row a one-store reader sees is store A's.
    perform pg_temp.check(pg_temp.ssx_try('staff_a', case t
        when 'invoice_promotion_selections' then
          format('select count(*)::text from public.invoice_promotion_selections where invoice_item_id = %L', pg_temp.ssx_id('item_a'))
        else format('select count(*)::text from public.%I where invoice_id = %L', t, pg_temp.ssx_id('inv_a')) end) = 'ok' || chr(9) || '1',
      format('Staff at store A see store A''s row of %s', t));
    perform pg_temp.check(pg_temp.ssx_try('anon', format('select count(*)::text from public.%I', t)) = '42501',
      format('the public key may not read %s', t));
    perform pg_temp.check(not has_table_privilege('authenticated', 'public.' || t, 'insert,update,delete,truncate'),
      format('signed-in logins may not write %s', t));
    perform pg_temp.check(pg_temp.ssx_try('owner', format('delete from public.%I returning 1', t)) = '42501',
      format('even an Owner may not delete from %s directly', t));
    -- One read, planned with InitPlans and no helper per row.
    begin
      perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.ssx_id('staff_a'), 'role', 'authenticated')::text, true);
      execute 'set local role authenticated';
      v_plan := '';
      for r in execute format('explain (costs off) select * from public.%I', t) loop v_plan := v_plan || r."QUERY PLAN" || chr(10); end loop;
      raise exception using errcode = 'SSX01', message = v_plan;
    exception when others then get stacked diagnostics v_plan = message_text;
    end;
    perform pg_temp.check(v_plan ~ 'InitPlan' and v_plan !~ '(user_has_store_access|current_user_role|is_owner_or_admin|current_user_store_ids)\(',
      format('the read of %s asks who you are once', t));
  end loop;

  -- The Invoices page's reads of one invoice, as Staff at store A.
  perform pg_temp.check(pg_temp.ssx_try('staff_a', format('select count(*)::text from public.invoice_items where invoice_id = %L', pg_temp.ssx_id('inv_a'))) = 'ok' || chr(9) || '1',
    'the page reads store A''s invoice lines');
  perform pg_temp.check(pg_temp.ssx_try('staff_a', format('select count(*)::text from public.invoice_promotion_selections where invoice_item_id in (select id from public.invoice_items where invoice_id = %L)', pg_temp.ssx_id('inv_a'))) = 'ok' || chr(9) || '1',
    'the page reads store A''s promotion picks');
  perform pg_temp.check(pg_temp.ssx_try('staff_a', format('select count(*)::text from public.invoice_revisions where invoice_id = %L', pg_temp.ssx_id('inv_a'))) = 'ok' || chr(9) || '1',
    'the page reads store A''s revisions');
  perform pg_temp.check(pg_temp.ssx_try('staff_a', format('select count(*)::text from public.invoice_items where invoice_id = %L', pg_temp.ssx_id('inv_b'))) = 'ok' || chr(9) || '0',
    'and none of store B''s lines, even by id');
  perform pg_temp.check(pg_temp.ssx_try('staff_a', format('select count(*)::text from public.invoice_payments where invoice_id = %L', pg_temp.ssx_id('inv_a'))) = 'ok' || chr(9) || '1',
    'payments as before: store A''s');
  -- The detail functions: store A answers, store B is refused.
  foreach v in array array['invoice_financial_position', 'invoice_revision_history', 'invoice_display_names'] loop
    perform pg_temp.check(split_part(pg_temp.ssx_try('staff_a', format('select public.%I(%L)::text', v, pg_temp.ssx_id('inv_a'))), chr(9), 1) = 'ok',
      format('%s answers for store A', v));
    perform pg_temp.check(split_part(pg_temp.ssx_try('staff_ab', format('select public.%I(%L)::text', v, pg_temp.ssx_id('inv_b'))), chr(9), 1) = 'ok',
      format('%s answers Staff at both stores for store B', v));
  end loop;
  perform pg_temp.check(pg_temp.ssx_try('staff_a', format('select public.invoice_revision_history(%L)::text', pg_temp.ssx_id('inv_b'))) = '42501',
    'invoice_revision_history refuses store B');

  -- The stores each login works at.
  for r in select * from (values
      ('owner', true, true, true), ('mgr_a', true, false, false), ('im_a', true, false, false),
      ('staff_a', true, false, false), ('staff_ab', true, true, false), ('pending', false, false, false),
      ('deleted', false, false, false), ('nostaff', false, false, false)) x(who, at_a, at_b, at_null) loop
    perform pg_temp.check(pg_temp.ssx_try(r.who, format('select concat_ws(''/'', public.user_has_store_access(%L), public.user_has_store_access(%L), public.user_has_store_access(null))', a, b))
        = 'ok' || chr(9) || concat_ws('/', r.at_a, r.at_b, r.at_null),
      format('user_has_store_access for %s: A %s, B %s, no store %s', r.who, r.at_a, r.at_b, r.at_null));
    v_exp := case when r.who = 'owner' then (select array_agg(s.id order by s.id) from public.stores s)::text
                  when r.at_b then (select array_agg(x order by x) from unnest(array[a, b]) x)::text
                  when r.at_a then array[a]::text
                  else '{}' end;
    perform pg_temp.check(pg_temp.ssx_try(r.who, 'select public.current_user_store_ids()::text') = 'ok' || chr(9) || v_exp,
      format('current_user_store_ids for %s', r.who));
  end loop;
  perform pg_temp.check(pg_temp.ssx_try('anon', 'select public.current_user_store_ids()::text') = '42501',
    'the public key may not ask current_user_store_ids');
end $$;

do $$ begin raise notice 'PASS: invoice lines, revisions, promotion picks, refunds and credit splits follow the invoice''s store; the Invoices page and the detail functions still answer for the reader''s stores'; end $$;
rollback;
