-- 427: the Dashboard, the Payment Summary's takings and the two new alerts.
--
-- Builds invented fixtures (stores, logins, invoices, payments, credit,
-- rewards, TikTok settlement lines), reads what the functions before 427
-- answer (the faults the audit of 9 Oct 2026 found: section 1), applies 427
-- inside this transaction (the same answers, a re-run that changes nothing,
-- the guards: section 2), then checks, as each role:
--   3  daily_payments_by_method: deleted invoices left out; wallet credit
--      still listed and marked; who may read it.
--   4  dashboard_credit_spend / _by_store: Monday weeks, the wallet payment's
--      Singapore day, sale statuses, the stores each login works at, a custom
--      range checked.
--   5  dashboard_summary: voucher uses this month, as the Reports page
--      counts them; 414's commission figures still there.
--   6  dashboard_alerts_summary: the transfer counts are the Transfers
--      card's; 'foc' is gone; settled TikTok orders with no imported order;
--      refunded or cancelled sales that still hold credit or rewards
--      (promotion vouchers and vouchers claimed from a reward included, and
--      open unlimited therapy: the Owner, 18 Oct 2026); customers without
--      source, only those added since 1 Aug 2026 (the Owner, 18 Oct 2026).
--   7  review_tiktok_settlement_without_order and the Reconciliation tab
--      (each line with its store and id, as the "Mark reviewed" button sends
--      it); the internal function refuses an actor named by the server who
--      is not an active Owner or Manager; the tab's other two kinds of row
--      name their store too (and a line that does not reconcile, its id).
--   8  the grants.
--
-- Disposable database only; everything is rolled back. The migration is
-- applied inside this transaction, so run the file on its own:
--   psql -X -v ON_ERROR_STOP=1 -f scripts/dashboard/tests/dashboard-427.sql
-- It needs production's functions as read on 10 Oct 2026 (427 refuses
-- otherwise). Every name, phone and email is invented (T427, the fictional
-- numbers +6149157xxxx, @sig.invalid). Every check runs; the file fails at the end if any did.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '300s';

create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
create temp table tx(k text primary key, v text);
create function pg_temp.tx(key text) returns text language sql as $$ select v from tx where k = key $$;

-- Run p_sql as one of the fixture's logins (a key in fx), 'anon' (the public
-- key, signed out) or 'server' (no request: the SQL editor, pg_cron). Says
-- 'ok', a tab and the result; or the SQLSTATE, a tab and the message.
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
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    return v_state || chr(9) || v_msg;
  end;
end $f$;
-- The answer of a call that must succeed, as jsonb (null when it returns nothing).
create function pg_temp.ok_as(p_who text, p_sql text) returns jsonb language plpgsql as $f$
declare v text := pg_temp.call_as(p_who, p_sql);
begin
  if split_part(v, chr(9), 1) <> 'ok' then raise exception 'FAIL: % as % was refused: %', p_sql, p_who, v; end if;
  return nullif(substr(v, 4), '')::jsonb;
end $f$;
create function pg_temp.state_as(p_who text, p_sql text) returns text language sql as
  $$ select split_part(pg_temp.call_as(p_who, p_sql), chr(9), 1) $$;

-- Singapore wall-clock time as a timestamp.
create function pg_temp.sgt(p text) returns timestamptz language sql immutable as
  $$ select p::timestamp at time zone 'Asia/Singapore' $$;
create function pg_temp.inv(p_key text, p_store text, p_status text, p_bd date, p_deleted boolean default false)
returns uuid language plpgsql as $f$
declare v uuid;
begin
  insert into public.invoices(invoice_no, store_id, customer_id, created_by, status, total_amount, business_date, deleted_at)
  values ('T427-' || pg_temp.tx('sfx') || '-' || p_key, pg_temp.fx(p_store), pg_temp.fx('cust'), pg_temp.fx('owner'),
          p_status::public.invoice_status, 0, p_bd, case when p_deleted then now() end)
  returning id into v;
  insert into fx values (p_key, v);
  return v;
end $f$;
create function pg_temp.item(p_inv text, p_voucher text default null) returns uuid language sql as $f$
  insert into public.invoice_items(invoice_id, product_id, quantity, unit_price, line_total, line_kind, line_voucher_id)
  values (pg_temp.fx(p_inv), pg_temp.fx('product'), 1, 10, 10, 'product', pg_temp.fx(p_voucher)) returning id $f$;
create function pg_temp.pay(p_inv text, p_method text, p_amount numeric, p_at timestamptz) returns uuid language sql as $f$
  insert into public.invoice_payments(invoice_id, payment_method_id, amount, received_by, effective_at, created_at)
  values (pg_temp.fx(p_inv), pg_temp.fx(p_method), p_amount, pg_temp.fx('owner'), p_at, p_at) returning id $f$;
create function pg_temp.alloc(p_inv text, p_amount numeric, p_payment uuid, p_reversed numeric default 0) returns uuid language sql as $f$
  insert into public.invoice_line_credit_allocations(invoice_id, lot_id, customer_id, category, amount, reversed_amount, payment_id)
  values (pg_temp.fx(p_inv), pg_temp.fx('lot'), pg_temp.fx('cust'), 'paid', p_amount, p_reversed, p_payment) returning id $f$;
create function pg_temp.lot(p_remaining numeric, p_status text default 'active', p_source text default 'credit_package',
                            p_source_id uuid default null) returns uuid language sql as $f$
  insert into public.customer_credit_lots(wallet_id, customer_id, category, original_amount, remaining_amount, source_type,
                                          source_record_id, status)
  values (pg_temp.fx('wallet'), pg_temp.fx('cust'), 'paid', greatest(p_remaining, 100), p_remaining, p_source, p_source_id, p_status) returning id $f$;
create function pg_temp.cps(p_inv text, p_lot uuid) returns uuid language sql as $f$
  insert into public.credit_package_sales(package_id, customer_id, invoice_id, package_name_snapshot, price_snapshot,
                                          credit_snapshot, classification_snapshot, credit_lot_id)
  values (pg_temp.fx('package'), pg_temp.fx('cust'), pg_temp.fx(p_inv), 'T427 Package', 100, 100, 'credit', p_lot) returning id $f$;
create function pg_temp.ent(p_status text, p_group uuid) returns uuid language sql as $f$
  insert into public.therapy_entitlements(entitlement_no, customer_id, store_id, package_name, entitlement_kind, voucher_qty,
                                          qualifying_amount, qualified_value, activation_deadline, status, qualification_group_id)
  values ('T427-E-' || substr(md5(random()::text), 1, 10), pg_temp.fx('cust'), pg_temp.fx('store_a'), 'T427 Reward', 'voucher', 5,
          0, 0, public.sg_today() + 30, p_status, p_group) returning id $f$;
create function pg_temp.reward_voucher(p_status text, p_source_type text, p_source uuid) returns uuid language sql as $f$
  insert into public.customer_reward_vouchers(customer_id, voucher_id, quantity, status, source_type, source_id, store_id)
  values (pg_temp.fx('cust'), pg_temp.fx('v1'), 1, p_status, p_source_type, p_source, pg_temp.fx('store_a')) returning id $f$;
-- An unlimited-therapy unit bought on an invoice, in a status. A started
-- unit gets its own 30 days, apart from every other (one customer may not
-- hold two of a package at once).
create function pg_temp.unit(p_inv text, p_status text) returns uuid language sql as $f$
  insert into public.purchased_therapy_entitlements(entitlement_no, customer_id, store_id, package_id, invoice_id, package_name,
                                                    duration_months, price_snapshot, purchase_date, activation_deadline, status,
                                                    activation_date, expiry_date)
  select 'T427-U-' || substr(md5(random()::text), 1, 10), pg_temp.fx('cust'), i.store_id, pg_temp.fx('utp'), i.id, 'T427 Unlimited',
         3, 100, '2026-09-01', public.sg_today() + 30, p_status,
         case when p_status in ('active', 'scheduled', 'expired') then x.d end,
         case when p_status in ('active', 'scheduled', 'expired') then x.d + 30 end
    from public.invoices i
   cross join (select date '2000-01-01' + 40 * (select count(*) from public.purchased_therapy_entitlements)::int as d) x
   where i.id = pg_temp.fx(p_inv) returning id $f$;
create function pg_temp.settle(p_key text, p_store text, p_order text, p_amount numeric, p_match text, p_confirmed boolean,
                               p_current boolean) returns uuid language plpgsql as $f$
declare v uuid;
begin
  insert into public.tiktok_settlement_rows(batch_id, store_id, row_no, order_id, transaction_type, txn_class, settlement_amount,
                                            revenue_amount, fee_amount, match_status, confirmed, is_current)
  values (pg_temp.fx('batch_' || p_store), pg_temp.fx(p_store), (select count(*) + 1 from public.tiktok_settlement_rows),
          'T427-' || pg_temp.tx('sfx') || '-' || p_order, 'Order', 'order', p_amount, p_amount + 2, -2, p_match,
          p_confirmed, p_current)
  returning id into v;
  insert into fx values (p_key, v);
  return v;
end $f$;
-- The Dashboard's alerts, as a login.
create function pg_temp.alerts(p_who text) returns jsonb language sql as
  $$ select pg_temp.ok_as(p_who, 'select public.dashboard_alerts_summary()::text') $$;
create function pg_temp.dpm(p_who text, p_from date, p_to date, p_store text) returns jsonb language sql as $$
  select pg_temp.ok_as(p_who, format(
    'select coalesce(jsonb_agg(jsonb_build_object(''day'', d.pay_date, ''method'', d.method_name, ''amount'', d.amount, ''n'', d.payment_count) order by d.pay_date, d.method_name), ''[]'')::text
       from public.daily_payments_by_method(%L, %L, %L) d where d.method_name like ''T427 %%''', p_from, p_to, pg_temp.fx(p_store))) $$;
create function pg_temp.credit(p_who text, p_period text, p_from date, p_to date, p_store text) returns jsonb language sql as $$
  select pg_temp.ok_as(p_who, format('select public.dashboard_credit_spend(%L, %L, %L, %L)::text', p_period, p_from, p_to, pg_temp.fx(p_store))) $$;
create function pg_temp.credit_stores(p_who text, p_period text, p_from date, p_to date) returns jsonb language sql as $$
  select pg_temp.ok_as(p_who, format(
    'select coalesce(jsonb_agg(jsonb_build_object(''store'', x.store_id, ''amount'', x.credit_spent, ''invoices'', x.invoices) order by x.credit_spent desc), ''[]'')::text
       from public.dashboard_credit_by_store(%L, %L, %L) x
      where x.store_id in (%L, %L)', p_period, p_from, p_to, pg_temp.fx('store_a'), pg_temp.fx('store_b'))) $$;

-- ═════ Fixtures ═════
do $$
declare sfx text := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  k text; v uuid; st_a uuid; st_b uuid; cust uuid; it uuid; mon date := date_trunc('week', public.sg_today())::date;
  ms date := date_trunc('month', public.sg_today())::date; p uuid; i int;
begin
  insert into tx values ('sfx', sfx);
  foreach k in array array['owner', 'admin', 'manager_a', 'staff_a', 'staff_b', 'nostaff'] loop
    insert into auth.users(id, email) values (gen_random_uuid(), 't427-' || k || '-' || lower(sfx) || '@sig.invalid') returning id into v;
    insert into fx values (k, v);
  end loop;
  insert into public.profiles(id, full_name, email, role, is_active)
  select pg_temp.fx(x.k), 'T427 ' || x.k, 't427-' || x.k || '-' || lower(sfx) || '@sig.invalid', x.role::public.user_role, true
    from (values ('owner', 'owner'), ('admin', 'admin'), ('manager_a', 'manager'), ('staff_a', 'staff'), ('staff_b', 'staff')) x(k, role);
  insert into public.stores(name, code, country_code) values ('T427 Store A ' || sfx, 'T427A' || sfx, 'SG') returning id into st_a;
  insert into public.stores(name, code, country_code) values ('T427 Store B ' || sfx, 'T427B' || sfx, 'SG') returning id into st_b;
  insert into fx values ('store_a', st_a), ('store_b', st_b);
  insert into public.user_store_assignments(user_id, store_id) values
    (pg_temp.fx('manager_a'), st_a), (pg_temp.fx('staff_a'), st_a), (pg_temp.fx('staff_b'), st_b);
  insert into public.customers(full_name, phone)
  values ('T427 Customer', '+61491574632') returning id into cust;
  insert into fx values ('cust', cust);
  insert into public.payment_methods(name) values ('T427 Cash ' || sfx) returning id into v; insert into fx values ('cash', v);
  insert into public.payment_methods(name, is_wallet_credit, wallet_category) values ('T427 Wallet ' || sfx, true, 'paid')
    returning id into v; insert into fx values ('wallet_pm', v);
  insert into public.customer_credit_wallets(customer_id) values (cust) returning id into v; insert into fx values ('wallet', v);
  insert into fx values ('lot', pg_temp.lot(1000, 'active', 'manual_adjustment'));
  insert into public.products(name, sku) values ('T427 Item', 'T427-' || sfx) returning id into v; insert into fx values ('product', v);
  insert into public.vouchers(name, code) values ('T427 Voucher One', 'T427V1' || sfx) returning id into v; insert into fx values ('v1', v);
  insert into public.vouchers(name, code) values ('T427 Voucher Two', 'T427V2' || sfx) returning id into v; insert into fx values ('v2', v);
  insert into public.credit_packages(name, customer_price, paid_credit_amount) values ('T427 Package', 100, 100) returning id into v;
  insert into fx values ('package', v);
  insert into public.premium_bundles(name, customer_payment_amount) values ('T427 Bundle', 100) returning id into v;
  insert into fx values ('bundle', v);
  insert into public.unlimited_therapy_packages(name, duration_months) values ('T427 Unlimited ' || sfx, 3) returning id into v;
  insert into fx values ('utp', v);
  insert into public.customer_source_options(label) values ('T427 Source ' || sfx) returning id into v;
  insert into fx values ('source', v);
  -- Customers with no source, around 1 Aug 2026 (Singapore): the last second
  -- of July, the first second of August; one with a source; one deleted.
  insert into public.customers(full_name, phone, created_at) values ('T427 July', '+61491570737', pg_temp.sgt('2026-07-31 23:59:59'))
    returning id into v; insert into fx values ('cust_jul', v);
  insert into public.customers(full_name, phone, created_at) values ('T427 August', '+61491572983', pg_temp.sgt('2026-08-01 00:00:00'))
    returning id into v; insert into fx values ('cust_aug', v);
  insert into public.customers(full_name, phone, created_at, source_option_id)
  values ('T427 Sourced', '+61491573770', pg_temp.sgt('2026-08-02 12:00'), pg_temp.fx('source'));
  insert into public.customers(full_name, phone, created_at, deleted_at)
  values ('T427 Deleted', '+61491573087', pg_temp.sgt('2026-08-03 12:00'), now());

  -- Takings on 6 Jul 2026 (Singapore): a live invoice at A (cash 100, wallet
  -- 30), a deleted one at A (cash 200), a live one at B (cash 40).
  perform pg_temp.inv('d_live', 'store_a', 'paid', '2026-07-06');
  perform pg_temp.pay('d_live', 'cash', 100, pg_temp.sgt('2026-07-06 10:00'));
  perform pg_temp.pay('d_live', 'wallet_pm', 30, pg_temp.sgt('2026-07-06 10:05'));
  perform pg_temp.inv('d_del', 'store_a', 'cancelled', '2026-07-06', true);
  perform pg_temp.pay('d_del', 'cash', 200, pg_temp.sgt('2026-07-06 11:00'));
  perform pg_temp.inv('d_b', 'store_b', 'paid', '2026-07-06');
  perform pg_temp.pay('d_b', 'cash', 40, pg_temp.sgt('2026-07-06 12:00'));

  -- Credit spent, August 2026. c_live: dated 1 Aug by its cash, its wallet
  -- payment at 00:30 on 5 Aug in Singapore (16:30 UTC on 4 Aug).
  perform pg_temp.inv('c_live', 'store_a', 'paid', '2026-08-01');
  perform pg_temp.pay('c_live', 'cash', 100, pg_temp.sgt('2026-08-01 12:00'));
  perform pg_temp.alloc('c_live', 50, pg_temp.pay('c_live', 'wallet_pm', 50, pg_temp.sgt('2026-08-05 00:30')));
  -- c_nopay: an allocation with no payment, on an invoice dated 10 Aug.
  perform pg_temp.inv('c_nopay', 'store_a', 'paid', '2026-08-10');
  perform pg_temp.alloc('c_nopay', 20, null);
  -- 12 Aug: waiting for its refund (still a sale), deleted, cancelled, at B,
  -- and one partly reversed (30, 10 of it reversed).
  perform pg_temp.inv('c_refreq', 'store_a', 'refund_requested', '2026-08-12');
  perform pg_temp.alloc('c_refreq', 25, pg_temp.pay('c_refreq', 'wallet_pm', 25, pg_temp.sgt('2026-08-12 10:00')));
  perform pg_temp.inv('c_del', 'store_a', 'paid', '2026-08-12', true);
  perform pg_temp.alloc('c_del', 70, pg_temp.pay('c_del', 'wallet_pm', 70, pg_temp.sgt('2026-08-12 10:00')));
  perform pg_temp.inv('c_cancel', 'store_a', 'cancelled', '2026-08-12');
  perform pg_temp.alloc('c_cancel', 15, pg_temp.pay('c_cancel', 'wallet_pm', 15, pg_temp.sgt('2026-08-12 10:00')));
  perform pg_temp.inv('c_b', 'store_b', 'paid', '2026-08-12');
  perform pg_temp.alloc('c_b', 40, pg_temp.pay('c_b', 'wallet_pm', 40, pg_temp.sgt('2026-08-12 15:00')));
  perform pg_temp.inv('c_rev', 'store_a', 'paid', '2026-08-12');
  perform pg_temp.alloc('c_rev', 30, pg_temp.pay('c_rev', 'wallet_pm', 30, pg_temp.sgt('2026-08-12 16:00')), 10);
  -- This week: one on the Sunday before it (outside a Monday week), one at
  -- 00:30 on its Monday in Singapore (16:30 UTC on the Sunday).
  perform pg_temp.inv('c_sun', 'store_a', 'paid', mon - 1);
  perform pg_temp.alloc('c_sun', 11, pg_temp.pay('c_sun', 'wallet_pm', 11, (mon - 1)::timestamp at time zone 'Asia/Singapore' + interval '12 hours'));
  perform pg_temp.inv('c_mon', 'store_a', 'paid', mon);
  perform pg_temp.alloc('c_mon', 13, pg_temp.pay('c_mon', 'wallet_pm', 13, mon::timestamp at time zone 'Asia/Singapore' + interval '30 minutes'));
  insert into tx values ('monday', mon::text);

  -- Voucher uses this month. vu_paid: two lines with a voucher, one without,
  -- and a voucher as its invoice-level discount (3 uses). Not counted: one
  -- paid last month, a deleted one, a cancelled one, one paid only with wallet
  -- credit. vu_b at B: one use.
  perform pg_temp.inv('vu_paid', 'store_a', 'paid', public.sg_today());
  update public.invoices set discount_voucher_id = pg_temp.fx('v2') where id = pg_temp.fx('vu_paid');
  perform pg_temp.item('vu_paid', 'v1'); perform pg_temp.item('vu_paid', 'v1'); perform pg_temp.item('vu_paid');
  perform pg_temp.pay('vu_paid', 'cash', 30, now());
  perform pg_temp.inv('vu_last', 'store_a', 'paid', ms - 1);
  perform pg_temp.item('vu_last', 'v1');
  perform pg_temp.pay('vu_last', 'cash', 10, (ms - 1)::timestamp at time zone 'Asia/Singapore' + interval '12 hours');
  perform pg_temp.inv('vu_del', 'store_a', 'paid', public.sg_today(), true);
  perform pg_temp.item('vu_del', 'v1'); perform pg_temp.pay('vu_del', 'cash', 10, now());
  perform pg_temp.inv('vu_cancel', 'store_a', 'cancelled', public.sg_today());
  perform pg_temp.item('vu_cancel', 'v1'); perform pg_temp.pay('vu_cancel', 'cash', 10, now());
  perform pg_temp.inv('vu_wallet', 'store_a', 'paid', public.sg_today());
  perform pg_temp.item('vu_wallet', 'v1'); perform pg_temp.pay('vu_wallet', 'wallet_pm', 10, now());
  perform pg_temp.inv('vu_b', 'store_b', 'paid', public.sg_today());
  perform pg_temp.item('vu_b', 'v2'); perform pg_temp.pay('vu_b', 'cash', 10, now());

  -- Transfers: one in transit to B for ten days, one received short at A.
  insert into public.warehouses(name, code) values ('T427 Warehouse ' || sfx, 'T427W' || sfx) returning id into v;
  insert into public.transfer_requests(transfer_type, source_type, source_id, dest_type, dest_id, status, requested_by, dispatched_at)
  values ('warehouse_to_store', 'warehouse', v, 'store', st_b, 'in_transit', pg_temp.fx('owner'), now() - interval '10 days');
  insert into public.transfer_requests(transfer_type, source_type, source_id, dest_type, dest_id, status, requested_by,
                                       dispatched_at, received_at, received_by, has_discrepancy, discrepancy_resolved)
  values ('warehouse_to_store', 'warehouse', v, 'store', st_a, 'received_with_discrepancy', pg_temp.fx('owner'),
          now() - interval '2 days', now() - interval '1 day', pg_temp.fx('owner'), true, false);

  -- TikTok settlement lines: O1 (two lines) and O2 settled with no order at
  -- A; O3 matched; O4 superseded; O5 not confirmed; O6 at B.
  insert into public.tiktok_import_batches(store_id, file_kind, file_name, status, uploaded_by)
  values (st_a, 'settlement', 'T427 A', 'confirmed', pg_temp.fx('owner')) returning id into v; insert into fx values ('batch_store_a', v);
  insert into public.tiktok_import_batches(store_id, file_kind, file_name, status, uploaded_by)
  values (st_b, 'settlement', 'T427 B', 'confirmed', pg_temp.fx('owner')) returning id into v; insert into fx values ('batch_store_b', v);
  perform pg_temp.settle('s1a', 'store_a', 'O1', 10, 'pending', true, true);
  perform pg_temp.settle('s1b', 'store_a', 'O1', 5, 'pending', true, true);
  perform pg_temp.settle('s2', 'store_a', 'O2', 7, 'pending', true, true);
  perform pg_temp.settle('s3', 'store_a', 'O3', 9, 'matched', true, true);
  perform pg_temp.settle('s4', 'store_a', 'O4', 9, 'pending', true, false);
  perform pg_temp.settle('s5', 'store_a', 'O5', 9, 'pending', false, true);
  perform pg_temp.settle('s6', 'store_b', 'O6', 9, 'pending', true, true);

  -- Refunded, cancelled and deleted sales, and what they still hold.
  perform pg_temp.inv('h01', 'store_a', 'refunded', '2026-09-01');                                    -- credit left: counted
  perform pg_temp.cps('h01', pg_temp.lot(100));
  perform pg_temp.inv('h02', 'store_a', 'cancelled', '2026-09-01');                                   -- credit all spent: not
  perform pg_temp.cps('h02', pg_temp.lot(0));
  perform pg_temp.inv('h03', 'store_a', 'refunded', '2026-09-01');                                    -- reward by its line: counted
  it := pg_temp.item('h03'); perform pg_temp.cps('h03', null);
  perform pg_temp.ent('pending_activation', md5('credit_pkg_item:' || it::text)::uuid);
  perform pg_temp.inv('h04', 'store_a', 'refunded', '2026-09-01');                                    -- reward by its sale: counted
  perform pg_temp.ent('pending_activation', public.credit_package_reward_group(pg_temp.cps('h04', null)));
  perform pg_temp.inv('h05', 'store_a', 'cancelled', '2026-09-01');                                   -- voucher held: counted
  perform pg_temp.reward_voucher('held', 'invoice_voucher_sale', pg_temp.item('h05'));
  perform pg_temp.inv('h06', 'store_a', 'paid', '2026-09-01', true);                                  -- deleted, bundle credit: counted
  insert into public.premium_bundle_sales(bundle_id, customer_id, invoice_id, bundle_name_snapshot, payment_snapshot,
                                          paid_credit_snapshot, bonus_credit_snapshot, voucher_qty_snapshot,
                                          classification_snapshot, paid_credit_lot_id)
  values (pg_temp.fx('bundle'), cust, pg_temp.fx('h06'), 'T427 Bundle', 100, 100, 0, 0, 'credit', pg_temp.lot(60));
  perform pg_temp.inv('h07', 'store_a', 'paid', '2026-09-01');                                        -- still a sale: not
  perform pg_temp.cps('h07', pg_temp.lot(100));
  perform pg_temp.inv('h08', 'store_b', 'refunded', '2026-09-01');                                    -- at B, split credit: counted at B
  insert into public.invoice_credit_splits(invoice_id, invoice_item_id, customer_id, amount, issued_lot_id)
  values (pg_temp.fx('h08'), pg_temp.item('h08'), cust, 40, pg_temp.lot(40));
  perform pg_temp.inv('h09', 'store_a', 'refunded', '2026-09-01');                                    -- qualification reward: counted
  insert into public.therapy_entitlement_invoices(entitlement_id, invoice_id) values (pg_temp.ent('pending_activation', null), pg_temp.fx('h09'));
  perform pg_temp.inv('h10', 'store_a', 'refunded', '2026-09-01');                                    -- reward already in use: not
  insert into public.therapy_entitlement_invoices(entitlement_id, invoice_id) values (pg_temp.ent('active', null), pg_temp.fx('h10'));
  perform pg_temp.inv('h11', 'store_a', 'refunded', '2026-09-01');                                    -- voucher redeemed: not
  perform pg_temp.reward_voucher('redeemed', 'invoice_voucher_sale', pg_temp.item('h11'));
  perform pg_temp.inv('h12', 'store_a', 'refunded', '2026-09-01');                                    -- credit reversed: not
  perform pg_temp.cps('h12', pg_temp.lot(100, 'reversed'));
  perform pg_temp.inv('h13', 'store_a', 'refunded', '2026-09-01');                                    -- instalment credit: counted
  perform pg_temp.lot(25, 'active', 'credit_package_progress', pg_temp.item('h13'));
  for i in 14 .. 17 loop                                                                              -- four more: counted
    perform pg_temp.inv('h' || i, 'store_a', 'cancelled', '2026-09-01');
    perform pg_temp.cps('h' || i, pg_temp.lot(5));
  end loop;
end $$;

-- ═════ 1. Before 427: the faults ═════
do $$
declare j jsonb;
begin
  j := pg_temp.dpm('owner', '2026-07-06', '2026-07-06', null);
  perform pg_temp.check((select sum((x->>'amount')::numeric) from jsonb_array_elements(j) x where x->>'method' like 'T427 Cash%') = 340,
    '1: before 427 the takings counted the deleted invoice''s S$200 (cash 340): ' || j::text);
  perform pg_temp.check(pg_temp.state_as('nostaff', 'select count(*)::text from public.daily_payments_by_method(null, null, null)') = 'ok',
    '1: before 427 a login that is not staff got an answer (empty) from the takings, not a refusal');
  j := pg_temp.credit('owner', 'custom', '2026-08-05', '2026-08-05', 'store_a');
  perform pg_temp.check((j->>'credit_spent')::numeric = 0,
    '1: before 427 credit was dated by its invoice (nothing on 5 Aug): ' || j::text);
  j := pg_temp.credit('owner', 'custom', '2026-08-12', '2026-08-12', 'store_a');
  perform pg_temp.check((j->>'credit_spent')::numeric = 20,
    '1: before 427 a sale waiting for its refund was left out (only the reversed one, 20): ' || j::text);
  perform pg_temp.check(jsonb_array_length(pg_temp.credit_stores('manager_a', 'all', null, null)) = 2,
    '1: before 427 a Manager saw the credit of a store they do not work at (all time)');
  j := pg_temp.alerts('owner');
  perform pg_temp.check(j ? 'foc' and not (j->'tiktok' ? 'settled_without_order') and not (j ? 'sales'),
    '1: before 427 the alerts had an unused FOC value and no settled-without-order or sales alert');
  perform pg_temp.check((j->'surveys'->>'customers_without_source')::int
                        = (select count(*) from public.customers c where c.deleted_at is null and c.source_option_id is null),
    '1: before 427 "Customers without source" counted every customer ever added, July''s import included: ' || (j->'surveys')::text);
  insert into tx values ('nosource_before', j->'surveys'->>'customers_without_source');
end $$;
create temp table t427_rec_acl as
  select coalesce(array_to_string(p.proacl, ','), '') as acl from pg_proc p
   where p.oid = 'public.report_tiktok_recon_exceptions(uuid)'::regprocedure;

-- ═════ 2. 427 applied: once, again (nothing changes), and its guards ═════
\ir ../../../supabase/427_dashboard_reports_and_takings.sql
create temp table t427_after as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5,
         coalesce(array_to_string(p.proacl, ','), '') as acl
    from pg_proc p where p.pronamespace = 'public'::regnamespace;
\ir ../../../supabase/427_dashboard_reports_and_takings.sql
savepoint t427_guard;
create or replace function public.dashboard_summary() returns jsonb language sql stable security definer
  set search_path = public as $f$ select '{}'::jsonb $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/427_dashboard_reports_and_takings.sql
\set ON_ERROR_STOP on
rollback to savepoint t427_guard;
release savepoint t427_guard;
select set_config('t427.refused_changed', :'LAST_ERROR_MESSAGE', true) as t427_kept \gset
savepoint t427_guard2;
create or replace function public.resolve_period(p_period text, p_from date default null, p_to date default null)
  returns table(date_from date, date_to date, prev_from date, prev_to date, label text) language sql stable
  as $f$ select null::date, null::date, null::date, null::date, 'x'::text $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/427_dashboard_reports_and_takings.sql
\set ON_ERROR_STOP on
rollback to savepoint t427_guard2;
release savepoint t427_guard2;
select set_config('t427.refused_relied', :'LAST_ERROR_MESSAGE', true) as t427_kept \gset
savepoint t427_guard3;
drop function public.review_tiktok_settlement_without_order(uuid[], text);
\set ON_ERROR_STOP off
\ir ../../../supabase/427_dashboard_reports_and_takings.sql
\set ON_ERROR_STOP on
rollback to savepoint t427_guard3;
release savepoint t427_guard3;
select set_config('t427.refused_part', :'LAST_ERROR_MESSAGE', true) as t427_kept \gset
savepoint t427_guard4;
alter table public.invoices rename column discount_voucher_id to t427_renamed;
\set ON_ERROR_STOP off
\ir ../../../supabase/427_dashboard_reports_and_takings.sql
\set ON_ERROR_STOP on
rollback to savepoint t427_guard4;
release savepoint t427_guard4;
select set_config('t427.refused_column', :'LAST_ERROR_MESSAGE', true) as t427_kept \gset
do $$
begin
  perform pg_temp.check(not exists (
      select fn, md5, acl from t427_after
      except select p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid)), coalesce(array_to_string(p.proacl, ','), '')
               from pg_proc p where p.pronamespace = 'public'::regnamespace)
    and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace) = (select count(*) from t427_after),
    '2: a second run of 427 changes no function or grant');
  perform pg_temp.check(current_setting('t427.refused_changed') like '427: public.dashboard_summary() is not the version this was tested against%',
    '2: a changed function at another version refuses: ' || current_setting('t427.refused_changed'));
  perform pg_temp.check(current_setting('t427.refused_relied') like '427: public.resolve_period(text,date,date) is missing or not the version read on 10 Oct 2026%',
    '2: a relied-on function at another version refuses: ' || current_setting('t427.refused_relied'));
  perform pg_temp.check(current_setting('t427.refused_part') like '427: only part of this migration is installed (1 of 2 new functions%',
    '2: part of it missing refuses: ' || current_setting('t427.refused_part'));
  perform pg_temp.check(current_setting('t427.refused_column') like '427: public.invoices is not shaped as read on 10 Oct 2026%',
    '2: a column read that is not there refuses: ' || current_setting('t427.refused_column'));
  perform pg_temp.check((select count(*) from public.tiktok_settlement_reviews) = 0
                        and not exists (select 1 from public.profiles where full_name = '427 check')
                        and not exists (select 1 from public.stores where name = '427 check store')
                        and not exists (select 1 from public.audit_logs where action = 'tiktok_settlement_reviewed_no_stock'),
    '2: the migration''s own check left no row');
  perform pg_temp.check(md5(pg_get_functiondef('public.payment_methods_in_range(date,date,uuid)'::regprocedure)) = 'f2458ea03365bf664691a8f2b3b68589',
    '2: payment_methods_in_range is unchanged');
  perform pg_temp.check((select coalesce(array_to_string(p.proacl, ','), '') from pg_proc p
                          where p.oid = 'public.report_tiktok_recon_exceptions(uuid)'::regprocedure) = (select acl from t427_rec_acl)
                        and (select acl from t427_rec_acl) <> '',
    '2: report_tiktok_recon_exceptions, dropped and made again for its two new columns, has exactly the grants it had: '
    || (select acl from t427_rec_acl));
end $$;

-- ═════ 3. The takings ═════
do $$
declare j jsonb;
begin
  j := pg_temp.dpm('owner', '2026-07-06', '2026-07-06', null);
  perform pg_temp.check(j = jsonb_build_array(
      jsonb_build_object('day', '2026-07-06', 'method', 'T427 Cash ' || pg_temp.tx('sfx'), 'amount', 140.00, 'n', 2),
      jsonb_build_object('day', '2026-07-06', 'method', 'T427 Wallet ' || pg_temp.tx('sfx'), 'amount', 30.00, 'n', 1)),
    '3: an Owner''s takings on 6 Jul leave the deleted invoice out (cash 140 from 2, wallet 30): ' || j::text);
  perform pg_temp.check(pg_temp.dpm('admin', '2026-07-06', '2026-07-06', null) = j, '3: an Admin sees what the Owner sees');
  j := pg_temp.dpm('manager_a', '2026-07-06', '2026-07-06', null);
  perform pg_temp.check((select sum((x->>'amount')::numeric) from jsonb_array_elements(j) x where x->>'method' like 'T427 Cash%') = 100,
    '3: a Manager at A sees A''s cash only (100): ' || j::text);
  perform pg_temp.check(pg_temp.dpm('staff_b', '2026-07-06', '2026-07-06', 'store_b')
                        = jsonb_build_array(jsonb_build_object('day', '2026-07-06', 'method', 'T427 Cash ' || pg_temp.tx('sfx'), 'amount', 40.00, 'n', 1)),
    '3: Staff at B see B''s takings');
  perform pg_temp.check(pg_temp.state_as('staff_b', format('select count(*)::text from public.daily_payments_by_method(null, null, %L)', pg_temp.fx('store_a'))) = '42501',
    '3: Staff asking for a store they do not work at are refused (42501)');
  perform pg_temp.check(pg_temp.state_as('nostaff', 'select count(*)::text from public.daily_payments_by_method(null, null, null)') = '42501'
                        and pg_temp.state_as('anon', 'select count(*)::text from public.daily_payments_by_method(null, null, null)') = '42501'
                        and pg_temp.state_as('nostaff', 'select count(*)::text from public.payment_methods_in_range(null, null, null)') = '42501',
    '3: a login that is not staff, and the anon key, are refused (42501), through payment_methods_in_range too');
  j := pg_temp.ok_as('owner', format('select jsonb_agg(jsonb_build_object(''m'', m.method_name, ''w'', m.is_wallet_credit) order by m.method_name)::text
                                        from public.payment_methods_in_range(%L, %L, null) m where m.method_name like ''T427 %%''', '2026-07-06', '2026-07-06'));
  perform pg_temp.check(j = jsonb_build_array(jsonb_build_object('m', 'T427 Cash ' || pg_temp.tx('sfx'), 'w', false),
                                              jsonb_build_object('m', 'T427 Wallet ' || pg_temp.tx('sfx'), 'w', true)),
    '3: payment_methods_in_range still lists the wallet method, marked as wallet credit: ' || j::text);
  perform pg_temp.check(pg_temp.state_as('server', 'select count(*)::text from public.daily_payments_by_method(null, null, null)') = 'ok',
    '3: the server (no login: pg_cron, the SQL editor) passes the check');
end $$;

-- ═════ 4. Settled from credit ═════
do $$
declare j jsonb;
begin
  j := pg_temp.credit('owner', 'custom', '2026-08-05', '2026-08-05', 'store_a');
  perform pg_temp.check((j->>'credit_spent')::numeric = 50 and (j->>'invoices')::int = 1,
    '4: credit counts on the Singapore day its wallet payment was taken (5 Aug, 00:30): ' || j::text);
  j := pg_temp.credit('owner', 'custom', '2026-08-01', '2026-08-01', 'store_a');
  perform pg_temp.check((j->>'credit_spent')::numeric = 0, '4: not on the invoice''s own day (1 Aug): ' || j::text);
  j := pg_temp.credit('owner', 'custom', '2026-08-10', '2026-08-10', 'store_a');
  perform pg_temp.check((j->>'credit_spent')::numeric = 20, '4: credit with no payment counts on the invoice''s sales day (10 Aug): ' || j::text);
  j := pg_temp.credit('owner', 'custom', '2026-08-12', '2026-08-12', 'store_a');
  perform pg_temp.check((j->>'credit_spent')::numeric = 45 and (j->>'invoices')::int = 2,
    '4: 12 Aug at A: the sale waiting for its refund (25) and the part reversed (30 - 10); not the deleted or cancelled ones: ' || j::text);
  perform pg_temp.check((pg_temp.credit('owner', 'custom', '2026-08-12', '2026-08-12', null)->>'credit_spent')::numeric
                        >= 85,
    '4: the Owner''s every-store figure includes B''s 40');
  perform pg_temp.check(pg_temp.credit_stores('owner', 'custom', '2026-08-12', '2026-08-12')
                        = jsonb_build_array(jsonb_build_object('store', pg_temp.fx('store_a'), 'amount', 45.00, 'invoices', 2),
                                            jsonb_build_object('store', pg_temp.fx('store_b'), 'amount', 40.00, 'invoices', 1)),
    '4: by store, for the Owner: A 45 (2), B 40 (1), largest first');
  perform pg_temp.check(pg_temp.credit_stores('manager_a', 'custom', '2026-08-12', '2026-08-12')
                        = jsonb_build_array(jsonb_build_object('store', pg_temp.fx('store_a'), 'amount', 45.00, 'invoices', 2)),
    '4: a Manager sees only the store they work at');
  perform pg_temp.check(pg_temp.credit_stores('manager_a', 'all', null, null)
                        = jsonb_build_array(jsonb_build_object('store', pg_temp.fx('store_a'), 'amount', 139.00, 'invoices', 6)),
    '4: all time too (A only: 50 + 20 + 25 + 20 + 11 + 13)');
  perform pg_temp.check((pg_temp.credit('manager_a', 'custom', '2026-08-12', '2026-08-12', null)->>'credit_spent')::numeric = 45,
    '4: a Manager''s every-store figure is their store''s');
  perform pg_temp.check(pg_temp.state_as('manager_a', format('select public.dashboard_credit_spend(''custom'', ''2026-08-12'', ''2026-08-12'', %L)::text', pg_temp.fx('store_b'))) = '42501',
    '4: a Manager asking for a store they do not work at is refused (42501), as dashboard_sales refuses');
  perform pg_temp.check(pg_temp.credit_stores('staff_b', 'custom', '2026-08-12', '2026-08-12')
                        = jsonb_build_array(jsonb_build_object('store', pg_temp.fx('store_b'), 'amount', 40.00, 'invoices', 1)),
    '4: Staff at B see B');
  j := pg_temp.credit('owner', 'week', null, null, 'store_a');
  perform pg_temp.check((j->>'credit_spent')::numeric = 13 and j->>'label' = 'This week',
    '4: "This week" starts on Monday (' || pg_temp.tx('monday') || '): 00:30 on Monday counts, the Sunday before does not: ' || j::text);
  perform pg_temp.check(pg_temp.credit_stores('owner', 'week', null, null)
                        = jsonb_build_array(jsonb_build_object('store', pg_temp.fx('store_a'), 'amount', 13.00, 'invoices', 1)),
    '4: by store, the same week');
  perform pg_temp.check((pg_temp.credit('owner', 'all', null, null, 'store_a')->>'credit_spent')::numeric = 50 + 20 + 25 + 20 + 11 + 13,
    '4: all time at A: every live sale''s credit, net of what was reversed');
  j := pg_temp.credit('owner', 'custom', '2026-08-01', '2026-08-31', 'store_a');
  perform pg_temp.check(j->>'label' = '01 Aug 2026 – 31 Aug 2026', '4: a custom range is labelled with its dates: ' || j::text);
  perform pg_temp.check(pg_temp.call_as('owner', 'select public.dashboard_credit_spend(''custom'', ''2026-08-12'', ''2026-08-01'', null)::text')
                        like '%The end date cannot be before the start date%'
                        and pg_temp.call_as('owner', 'select count(*)::text from public.dashboard_credit_by_store(''custom'', ''2026-08-12'', ''2026-08-01'')')
                        like '%The end date cannot be before the start date%'
                        and pg_temp.call_as('owner', 'select public.dashboard_credit_spend(''fortnight'', null, null, null)::text')
                        like '%Unknown period%',
    '4: a reversed custom range and an unknown period are refused, as the Sales panel refuses them');
  perform pg_temp.check(pg_temp.state_as('nostaff', 'select public.dashboard_credit_spend(''day'', null, null, null)::text') = '42501'
                        and pg_temp.state_as('nostaff', 'select count(*)::text from public.dashboard_credit_by_store(''day'', null, null)') = '42501',
    '4: a login that is not staff is refused');
end $$;

-- ═════ 5. Voucher uses this month ═════
do $$
declare j jsonb; v_other int;
begin
  j := pg_temp.ok_as('manager_a', 'select public.dashboard_summary()::text');
  perform pg_temp.check((j->>'voucher_uses_month')::int = 3,
    '5: a Manager at A: two lines and one invoice-level voucher on the sale paid this month (3); not last month''s, the deleted, the cancelled or the wallet-only one: ' || (j->>'voucher_uses_month'));
  -- Uses at stores outside the fixture, counted the same way, so the Owner's
  -- figure can be checked on a database that holds other data.
  select coalesce(sum(n), 0) into v_other from (
    select (select count(*) from public.invoice_items it where it.invoice_id = e.invoice_id and it.line_voucher_id is not null)
           + (select count(*) from public.invoices iv where iv.id = e.invoice_id and iv.discount_voucher_id is not null) n
      from (select p.invoice_id from public.invoice_payments p join public.invoices i on i.id = p.invoice_id
              join public.payment_methods m on m.id = p.payment_method_id
             where i.deleted_at is null and public.invoice_counts_as_sale(i.status::text) and not m.is_wallet_credit
               and i.store_id not in (pg_temp.fx('store_a'), pg_temp.fx('store_b'))
               and public.payment_sales_date(p.effective_at, p.created_at) between date_trunc('month', public.sg_today())::date and public.sg_today()
             group by p.invoice_id) e) x;
  j := pg_temp.ok_as('owner', 'select public.dashboard_summary()::text');
  perform pg_temp.check((j->>'voucher_uses_month')::int = 4 + v_other,
    '5: the Owner counts B''s use too (4, plus ' || v_other || ' elsewhere): ' || (j->>'voucher_uses_month'));
  perform pg_temp.check(j ? 'unpaid_commission' and j ? 'commission_deductions' and j ? 'blocked_commission'
                        and j ? 'therapy_awaiting' and j ? 'discount_today' and j ? 'today_sales' and j ? 'role',
    '5: every key the summary sent is still sent (414''s commission figures included)');
  perform pg_temp.check(pg_temp.state_as('staff_a', 'select public.dashboard_summary()::text') = '42501',
    '5: Staff are still refused the summary');
end $$;

-- ═════ 6. The alerts ═════
do $$
declare j jsonb; t jsonb; v_who text; v_other int; v_nos jsonb; v_base int; it uuid;
begin
  foreach v_who in array array['owner', 'manager_a', 'staff_a', 'staff_b'] loop
    j := pg_temp.alerts(v_who);
    t := pg_temp.ok_as(v_who, 'select public.transfer_receipt_alerts()::text');
    perform pg_temp.check(j->'transfers' = jsonb_build_object('awaiting_receipt', t->'awaiting_receipt', 'overdue_7d', t->'overdue',
                                                              'open_discrepancies', t->'open_discrepancies'),
      '6: ' || v_who || '''s transfer alerts are the Transfers card''s counts: ' || (j->'transfers')::text);
    perform pg_temp.check(not (j ? 'foc'), '6: ' || v_who || ': the unused FOC value is gone');
  end loop;
  perform pg_temp.check((pg_temp.alerts('staff_a')->'transfers'->>'awaiting_receipt')::int = 0
                        and (pg_temp.alerts('staff_b')->'transfers'->>'awaiting_receipt')::int >= 1
                        and (pg_temp.alerts('staff_b')->'transfers'->>'overdue_7d')::int >= 1,
    '6: the transfer counts follow the stores: B''s transfer in transit is B''s staff''s, not A''s');

  select count(distinct (r.store_id, r.order_id)) into v_other from public.tiktok_settlement_rows r
   where r.confirmed and r.is_current and r.match_status = 'pending'
     and r.store_id not in (pg_temp.fx('store_a'), pg_temp.fx('store_b'));
  j := pg_temp.alerts('staff_a');
  perform pg_temp.check((j->'tiktok'->>'settled_without_order')::int = 3 + v_other,
    '6: settled with no imported order: O1 (two lines) and O2 at A, O6 at B; not matched, superseded or unconfirmed lines (3, plus ' || v_other || ' elsewhere): ' || (j->'tiktok')::text);

  v_nos := (select jsonb_agg('T427-' || pg_temp.tx('sfx') || '-' || x order by 'T427-' || pg_temp.tx('sfx') || '-' || x)
              from unnest(array['h01', 'h03', 'h04', 'h05', 'h06', 'h09', 'h13', 'h14', 'h15', 'h16']) x);
  j := pg_temp.alerts('manager_a');
  perform pg_temp.check((j->'sales'->>'holding_benefits')::int = 11 and j->'sales'->'invoice_nos' = v_nos,
    '6: a Manager at A: 11 refunded, cancelled or deleted sales still hold credit or rewards (package credit left, rewards by line or by sale, a voucher held, bundle credit on a deleted invoice, a qualification reward, instalment credit, four more); the first ten listed, in order: ' || (j->'sales')::text);
  j := pg_temp.alerts('staff_b');
  perform pg_temp.check(j->'sales' = jsonb_build_object('holding_benefits', 1, 'invoice_nos', jsonb_build_array('T427-' || pg_temp.tx('sfx') || '-h08')),
    '6: Staff at B see B''s one (split credit left): ' || (j->'sales')::text);
  j := pg_temp.alerts('owner');
  perform pg_temp.check((j->'sales'->>'holding_benefits')::int >= 12 and jsonb_array_length(j->'sales'->'invoice_nos') = 10,
    '6: the Owner sees both stores'' (12 or more), ten listed: ' || (j->'sales')::text);

  -- Two more kinds of vouchers still held. h18: a promotion on a line gave
  -- vouchers (issue_promotion_vouchers_for_invoice: 'held', by the line).
  -- h19: the sale's reward was claimed in full, so the reward is 'active'
  -- and its vouchers are held through the reward (claim_entitlement_vouchers:
  -- 'voucher_claim', with the reward's id). Each is counted once.
  v_base := (pg_temp.alerts('manager_a')->'sales'->>'holding_benefits')::int;
  perform pg_temp.inv('h18', 'store_a', 'refunded', '2026-09-01');
  perform pg_temp.reward_voucher('held', 'invoice_promotion_voucher', pg_temp.item('h18'));
  perform pg_temp.check((pg_temp.alerts('manager_a')->'sales'->>'holding_benefits')::int = v_base + 1,
    '6: a refunded sale whose promotion vouchers are still held is counted (' || v_base || ' + 1)');
  v_base := (pg_temp.alerts('manager_a')->'sales'->>'holding_benefits')::int;
  perform pg_temp.inv('h19', 'store_a', 'refunded', '2026-09-01');
  it := pg_temp.item('h19');
  insert into public.customer_reward_vouchers(customer_id, voucher_id, entitlement_id, quantity, status, source_type, source_id, store_id)
  values (pg_temp.fx('cust'), pg_temp.fx('v1'), pg_temp.ent('active', md5('credit_pkg_item:' || it::text)::uuid), 5, 'held',
          'voucher_claim', gen_random_uuid(), pg_temp.fx('store_a'));
  perform pg_temp.check((pg_temp.alerts('manager_a')->'sales'->>'holding_benefits')::int = v_base + 1,
    '6: a refunded sale whose reward was claimed in full, its vouchers still held, is counted (' || v_base || ' + 1)');
  -- Not counted: a promotion voucher revoked, and claimed vouchers redeemed.
  v_base := (pg_temp.alerts('manager_a')->'sales'->>'holding_benefits')::int;
  perform pg_temp.inv('h20', 'store_a', 'refunded', '2026-09-01');
  perform pg_temp.reward_voucher('revoked', 'invoice_promotion_voucher', pg_temp.item('h20'));
  perform pg_temp.inv('h21', 'store_a', 'cancelled', '2026-09-01');
  it := pg_temp.item('h21');
  insert into public.customer_reward_vouchers(customer_id, voucher_id, entitlement_id, quantity, status, source_type, source_id, store_id)
  values (pg_temp.fx('cust'), pg_temp.fx('v1'), pg_temp.ent('active', md5('credit_pkg_item:' || it::text)::uuid), 5, 'redeemed',
          'voucher_claim', gen_random_uuid(), pg_temp.fx('store_a'));
  perform pg_temp.check((pg_temp.alerts('manager_a')->'sales'->>'holding_benefits')::int = v_base,
    '6: a revoked promotion voucher and redeemed claimed vouchers are not counted (' || v_base || ')');

  -- Unlimited therapy bought on the sale and still open (the Owner, 18 Oct
  -- 2026): waiting to start, booked to start, or running. Each sale once.
  v_base := (pg_temp.alerts('manager_a')->'sales'->>'holding_benefits')::int;
  perform pg_temp.inv('u1', 'store_a', 'refunded', '2026-09-01');
  perform pg_temp.unit('u1', 'pending_activation'); perform pg_temp.unit('u1', 'pending_activation');
  perform pg_temp.inv('u2', 'store_a', 'cancelled', '2026-09-01');
  perform pg_temp.unit('u2', 'scheduled');
  perform pg_temp.inv('u3', 'store_a', 'paid', '2026-09-01', true);
  perform pg_temp.unit('u3', 'active');
  j := pg_temp.alerts('manager_a');
  perform pg_temp.check((j->'sales'->>'holding_benefits')::int = v_base + 3,
    '6: open unlimited therapy on a refunded sale (two units, counted once), a cancelled one (booked) and a deleted one (running) is counted ('
    || v_base || ' + 3): ' || (j->'sales')::text);
  -- Not counted: units refunded, cancelled or expired, and open units on a
  -- sale that still stands.
  v_base := (j->'sales'->>'holding_benefits')::int;
  perform pg_temp.inv('u4', 'store_a', 'refunded', '2026-09-01');
  perform pg_temp.unit('u4', 'refunded'); perform pg_temp.unit('u4', 'expired');
  perform pg_temp.inv('u5', 'store_a', 'cancelled', '2026-09-01');
  perform pg_temp.unit('u5', 'cancelled');
  perform pg_temp.inv('u6', 'store_a', 'paid', '2026-09-01');
  perform pg_temp.unit('u6', 'pending_activation');
  perform pg_temp.inv('u7', 'store_a', 'refund_requested', '2026-09-01');
  perform pg_temp.unit('u7', 'active');
  perform pg_temp.check((pg_temp.alerts('manager_a')->'sales'->>'holding_benefits')::int = v_base,
    '6: refunded, cancelled and expired units, and open units on a sale still standing (paid, or waiting for its refund), are not counted (' || v_base || ')');
  -- The stores: a refunded sale at B with a running unit is B's.
  v_other := (pg_temp.alerts('staff_b')->'sales'->>'holding_benefits')::int;
  perform pg_temp.inv('u8', 'store_b', 'refunded', '2026-09-01');
  perform pg_temp.unit('u8', 'active');
  perform pg_temp.check((pg_temp.alerts('staff_b')->'sales'->>'holding_benefits')::int = v_other + 1
                        and (pg_temp.alerts('manager_a')->'sales'->>'holding_benefits')::int = v_base
                        and pg_temp.alerts('staff_b')->'sales'->'invoice_nos' ? ('T427-' || pg_temp.tx('sfx') || '-u8'),
    '6: open unlimited therapy at B is counted and named for Staff at B, not for the Manager at A');

  -- Customers without source (the Owner, 18 Oct 2026): only those added
  -- since 1 Aug 2026, Singapore time; the date is sent for the tile.
  j := pg_temp.alerts('staff_a');
  v_base := (j->'surveys'->>'customers_without_source')::int;
  perform pg_temp.check(v_base = (select count(*) from public.customers c where c.deleted_at is null and c.source_option_id is null
                                    and (c.created_at at time zone 'Asia/Singapore')::date >= '2026-08-01')
                        and j->'surveys'->>'customers_without_source_since' = '2026-08-01'
                        and v_base < pg_temp.tx('nosource_before')::int,
    '6: customers without source count only those added since 1 Aug 2026 (Singapore), deleted and sourced ones left out ('
    || v_base || ', was ' || pg_temp.tx('nosource_before') || '): ' || (j->'surveys')::text);
  update public.customers set created_at = pg_temp.sgt('2026-08-01 00:00:00') where id = pg_temp.fx('cust_jul');
  perform pg_temp.check((pg_temp.alerts('staff_a')->'surveys'->>'customers_without_source')::int = v_base + 1,
    '6: a customer added at midnight on 1 Aug in Singapore (16:00 UTC on 31 Jul) is counted; one second earlier was not');
  update public.customers set source_option_id = pg_temp.fx('source') where id in (pg_temp.fx('cust_jul'), pg_temp.fx('cust_aug'));
  perform pg_temp.check((pg_temp.alerts('staff_a')->'surveys'->>'customers_without_source')::int = v_base - 1,
    '6: a customer given a source leaves the count');

  perform pg_temp.check(pg_temp.state_as('nostaff', 'select public.dashboard_alerts_summary()::text') = '42501'
                        and pg_temp.state_as('anon', 'select public.dashboard_alerts_summary()::text') = '42501',
    '6: a login that is not staff, and the anon key, are refused');
end $$;

-- ═════ 7. Reviewed: needs no stock taken off ═════
do $$
declare j jsonb; v_before int; v_sql text;
begin
  v_before := (pg_temp.alerts('owner')->'tiktok'->>'settled_without_order')::int;
  j := pg_temp.ok_as('owner', format('select jsonb_agg(e.order_id order by e.order_id)::text from public.report_tiktok_recon_exceptions(%L) e where e.kind = ''settlement_without_order''', pg_temp.fx('store_a')));
  perform pg_temp.check(j = jsonb_build_array('T427-' || pg_temp.tx('sfx') || '-O1', 'T427-' || pg_temp.tx('sfx') || '-O1', 'T427-' || pg_temp.tx('sfx') || '-O2'),
    '7: before any review the Reconciliation tab lists O1''s two lines and O2: ' || j::text);
  j := pg_temp.ok_as('manager_a', format('select jsonb_agg(jsonb_build_object(''row'', e.settlement_row_id, ''store'', e.store_id) order by e.settlement_row_id)::text
                                            from public.report_tiktok_recon_exceptions(%L) e where e.kind = ''settlement_without_order''', pg_temp.fx('store_a')));
  perform pg_temp.check(j = (select jsonb_agg(jsonb_build_object('row', x, 'store', pg_temp.fx('store_a')) order by x)
                               from unnest(array[pg_temp.fx('s1a'), pg_temp.fx('s1b'), pg_temp.fx('s2')]) x),
    '7: each line names its store and its id, which the "Mark reviewed" button sends: ' || j::text);
  v_sql := format('select public.review_tiktok_settlement_without_order(array[%L, %L]::uuid[], %L)::text', pg_temp.fx('s1a'), pg_temp.fx('s1b'), 'Sold before the app tracked TikTok stock');
  perform pg_temp.check(pg_temp.state_as('staff_a', v_sql) = '42501' and pg_temp.state_as('admin', v_sql) = '42501'
                        and pg_temp.state_as('nostaff', v_sql) = '42501' and pg_temp.state_as('anon', v_sql) = '42501',
    '7: Staff, Admins, a login that is not staff and the anon key may not review');
  perform pg_temp.check(pg_temp.state_as('manager_a', format('select public.review_tiktok_settlement_without_order(array[%L]::uuid[], ''x'')::text', pg_temp.fx('s6'))) = '42501',
    '7: a Manager may not review a line of a store they do not work at');
  perform pg_temp.check(pg_temp.state_as('staff_a', format('select public.tiktok_settlement_review_record(array[%L]::uuid[], ''x'', %L)::text', pg_temp.fx('s2'), pg_temp.fx('owner'))) = '42501',
    '7: the internal function is not a signed-in login''s to call');
  perform pg_temp.check(pg_temp.call_as('manager_a', format('select public.review_tiktok_settlement_without_order(array[%L]::uuid[], ''  '')::text', pg_temp.fx('s1a'))) like '%A reason is required%'
                        and pg_temp.call_as('manager_a', 'select public.review_tiktok_settlement_without_order(array[]::uuid[], ''x'')::text') like '%Choose at least one settlement line%'
                        and pg_temp.call_as('manager_a', format('select public.review_tiktok_settlement_without_order(array[%L]::uuid[], ''x'')::text', gen_random_uuid())) like '%was not found%'
                        and pg_temp.call_as('manager_a', format('select public.review_tiktok_settlement_without_order(array[%L]::uuid[], ''x'')::text', pg_temp.fx('s3'))) like '%is not a confirmed line still waiting for its order%'
                        and pg_temp.call_as('manager_a', format('select public.review_tiktok_settlement_without_order(array[%L]::uuid[], ''x'')::text', pg_temp.fx('s4'))) like '%is not a confirmed line still waiting for its order%'
                        and pg_temp.call_as('manager_a', format('select public.review_tiktok_settlement_without_order(array[%L]::uuid[], ''x'')::text', pg_temp.fx('s5'))) like '%is not a confirmed line still waiting for its order%'
                        and pg_temp.call_as('manager_a', format('select public.review_tiktok_settlement_without_order(array[%L]::uuid[], %L)::text', pg_temp.fx('s1a'), repeat('x', 2001))) like '%too long%',
    '7: no reason, no line, an unknown line, a matched, superseded or unconfirmed line, and a reason over 2,000 characters are refused');
  perform pg_temp.check(not exists (select 1 from public.tiktok_settlement_reviews), '7: nothing refused was recorded');
  j := pg_temp.ok_as('manager_a', v_sql);
  perform pg_temp.check(j = '{"reviewed": 2, "already_reviewed": 0}'::jsonb, '7: the Manager at A reviews O1''s two lines: ' || j::text);
  perform pg_temp.check((pg_temp.alerts('owner')->'tiktok'->>'settled_without_order')::int = v_before - 1,
    '7: O1 leaves the Dashboard''s count');
  j := pg_temp.ok_as('owner', format('select jsonb_agg(e.order_id order by e.order_id)::text from public.report_tiktok_recon_exceptions(%L) e where e.kind = ''settlement_without_order''', pg_temp.fx('store_a')));
  perform pg_temp.check(j = jsonb_build_array('T427-' || pg_temp.tx('sfx') || '-O2'), '7: and the Reconciliation tab: only O2 is left: ' || j::text);
  j := pg_temp.ok_as('owner', format('select public.review_tiktok_settlement_without_order(array[%L, %L]::uuid[], ''again'')::text', pg_temp.fx('s1a'), pg_temp.fx('s2')));
  perform pg_temp.check(j = '{"reviewed": 1, "already_reviewed": 1}'::jsonb, '7: a line already reviewed is left as it was; the Owner reviews O2: ' || j::text);
  perform pg_temp.check((select count(*) from public.tiktok_settlement_reviews r where r.settlement_row_id in (pg_temp.fx('s1a'), pg_temp.fx('s1b'))
                          and r.reviewed_by = pg_temp.fx('manager_a') and r.reason = 'Sold before the app tracked TikTok stock'
                          and r.decision = 'no_stock_needed') = 2
                        and (select reason from public.tiktok_settlement_reviews where settlement_row_id = pg_temp.fx('s2')) = 'again',
    '7: each review keeps who, why and the decision; the first reason is not overwritten');
  perform pg_temp.check((select count(*) from public.audit_logs a where a.action = 'tiktok_settlement_reviewed_no_stock'
                          and a.record_id in (pg_temp.fx('s1a'), pg_temp.fx('s1b'), pg_temp.fx('s2')) and a.module = 'tiktok_import') = 3
                        and (select count(*) from public.audit_logs a where a.action = 'tiktok_settlement_reviewed_no_stock'
                              and a.record_id = pg_temp.fx('s1a') and a.changed_by = pg_temp.fx('manager_a') and a.actor_role = 'manager') = 1,
    '7: one audit entry per line reviewed, naming who');
  perform pg_temp.check((select match_status from public.tiktok_settlement_rows where id = pg_temp.fx('s2')) = 'pending',
    '7: the settlement line itself is not changed');
  perform pg_temp.check(pg_temp.state_as('manager_a', 'select count(*)::text from public.tiktok_settlement_reviews') = '42501',
    '7: no signed-in login may read the reviews table directly');
end $$;

-- The internal function's own check of the actor it is given. A one-off
-- repair runs as the server and names the actor, so this check is the only
-- guard there. Every login below works at A, so the store check cannot be
-- what refuses them.
do $$
declare v uuid; k text; v_sql text;
begin
  foreach k in array array['admin_at_a', 'inactive', 'deleted', 'pending'] loop
    insert into auth.users(id, email) values (gen_random_uuid(), 't427-x-' || k || '-' || lower(pg_temp.tx('sfx')) || '@sig.invalid')
      returning id into v;
    insert into public.profiles(id, full_name, email, role, is_active, deleted_at, invitation_status)
    values (v, 'T427 ' || k, 't427-x-' || k || '-' || lower(pg_temp.tx('sfx')) || '@sig.invalid',
            (case when k = 'admin_at_a' then 'admin' else 'manager' end)::public.user_role, k <> 'inactive',
            case when k = 'deleted' then now() end, case when k = 'pending' then 'pending' end);
    insert into public.user_store_assignments(user_id, store_id) values (v, pg_temp.fx('store_a'));
    insert into fx values ('x_' || k, v);
  end loop;
  foreach k in array array['staff_a', 'x_admin_at_a', 'x_inactive', 'x_deleted', 'x_pending'] loop
    v_sql := format('select public.tiktok_settlement_review_record(array[%L]::uuid[], ''x'', %L)::text', pg_temp.fx('s2'), pg_temp.fx(k));
    perform pg_temp.check(pg_temp.state_as('server', v_sql) = '42501',
      '7: the server naming ' || k || ' as the actor is refused (42501): ' || pg_temp.call_as('server', v_sql));
  end loop;
  perform pg_temp.check(pg_temp.call_as('server', format('select public.tiktok_settlement_review_record(array[%L]::uuid[], ''x'', %L)::text',
                                                         pg_temp.fx('s2'), pg_temp.fx('manager_a')))
                        = 'ok' || chr(9) || '{"reviewed": 0, "already_reviewed": 1}',
    '7: the server naming an active Manager at A is accepted (the line is already reviewed, so nothing changes)');
end $$;

-- The Reconciliation tab's other two kinds of row name their store too: an
-- imported order with stock taken off and no settlement (no settlement line,
-- so no line id), and a settlement line that does not reconcile (its id).
do $$
declare v uuid; j jsonb;
begin
  insert into public.tiktok_order_state(store_id, order_id, seller_sku, deducted_qty, last_status)
  values (pg_temp.fx('store_a'), 'T427-' || pg_temp.tx('sfx') || '-OWS', 'T427-SKU-OWS', 1, 'T427 Shipped');
  -- A confirmed line cannot be changed, so it is made already not reconciling.
  insert into public.tiktok_settlement_rows(batch_id, store_id, row_no, order_id, transaction_type, txn_class, settlement_amount,
                                            revenue_amount, fee_amount, reconciled, match_status, confirmed, is_current)
  values (pg_temp.fx('batch_store_a'), pg_temp.fx('store_a'), (select count(*) + 1 from public.tiktok_settlement_rows),
          'T427-' || pg_temp.tx('sfx') || '-DIFF', 'Order', 'order', 10, 20, -2, false, 'matched', true, true)
  returning id into v;
  insert into fx values ('sdiff', v);
  j := pg_temp.ok_as('owner', format(
    'select jsonb_agg(jsonb_build_object(''kind'', e.kind, ''order'', e.order_id, ''store'', e.store_id, ''row'', e.settlement_row_id) order by e.kind)::text
       from public.report_tiktok_recon_exceptions(%L) e where e.order_id in (%L, %L)',
    pg_temp.fx('store_a'), 'T427-' || pg_temp.tx('sfx') || '-OWS', 'T427-' || pg_temp.tx('sfx') || '-DIFF'));
  perform pg_temp.check(j = jsonb_build_array(
                              jsonb_build_object('kind', 'order_without_settlement', 'order', 'T427-' || pg_temp.tx('sfx') || '-OWS',
                                                 'store', pg_temp.fx('store_a'), 'row', null),
                              jsonb_build_object('kind', 'reconciliation_difference', 'order', 'T427-' || pg_temp.tx('sfx') || '-DIFF',
                                                 'store', pg_temp.fx('store_a'), 'row', pg_temp.fx('sdiff'))),
    '7: an order with no settlement names its store and no line; a line that does not reconcile names its store and its id: ' || coalesce(j::text, 'nothing'));
end $$;

-- ═════ 8. Grants ═════
do $$
begin
  perform pg_temp.check(not has_function_privilege('anon', 'public.tiktok_settlement_review_record(uuid[],text,uuid)', 'execute')
                        and not has_function_privilege('authenticated', 'public.tiktok_settlement_review_record(uuid[],text,uuid)', 'execute')
                        and has_function_privilege('service_role', 'public.tiktok_settlement_review_record(uuid[],text,uuid)', 'execute'),
    '8: the internal review function is the service role''s alone');
  perform pg_temp.check(not has_function_privilege('anon', 'public.review_tiktok_settlement_without_order(uuid[],text)', 'execute')
                        and has_function_privilege('authenticated', 'public.review_tiktok_settlement_without_order(uuid[],text)', 'execute'),
    '8: the page function is signed-in logins'', not the anon key''s');
  perform pg_temp.check(not has_table_privilege('authenticated', 'public.tiktok_settlement_reviews', 'select,insert,update,delete')
                        and not has_table_privilege('anon', 'public.tiktok_settlement_reviews', 'select,insert,update,delete')
                        and has_table_privilege('service_role', 'public.tiktok_settlement_reviews', 'select')
                        and not has_table_privilege('service_role', 'public.tiktok_settlement_reviews', 'insert,update,delete'),
    '8: the reviews table: no client role; the service role reads it');
  perform pg_temp.check(bool_and(has_function_privilege('authenticated', to_regprocedure('public.' || f), 'execute')
                                 and not has_function_privilege('anon', to_regprocedure('public.' || f), 'execute')),
    '8: the changed functions keep their grants (signed-in logins, not anon)')
    from unnest(array['daily_payments_by_method(date,date,uuid)', 'dashboard_credit_spend(text,date,date,uuid)',
                      'dashboard_credit_by_store(text,date,date)', 'dashboard_alerts_summary()', 'dashboard_summary()',
                      'report_tiktok_recon_exceptions(uuid)']) f;
end $$;

do $$
declare v_n int; v_m text;
begin
  select count(*), string_agg(f.msg, ' | ' order by f.n) into v_n, v_m from failed f;
  if v_n > 0 then raise exception '% check(s) failed: %', v_n, v_m; end if;
  raise notice 'ALL PASS';
end $$;
rollback;
