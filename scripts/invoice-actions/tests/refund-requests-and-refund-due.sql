-- 409: refund requests, the refund still due, and the list's Outstanding.
--
-- The Owner's rules (approved 9 Oct 2026, audit findings INVOICES-CREATE-1,
-- -3 and -6): staff raise refunds and cancellations through the guided flow
-- as a request, and the retired request_invoice_action is no longer a client
-- endpoint; rejecting a request leaves the invoice as its payments say (an
-- invoice the old request moved to refund_requested or cancellation_requested
-- goes back to the status its payments imply, and nothing else moves); the
-- refund due on a cancelled invoice can be recorded as paid back by an Owner
-- or Manager, through the original payment sources, once and audited; a
-- cancelled, refunded or FOC invoice owes nothing in the list.
-- The review of 9 Oct 2026 added: putting a rejected request's invoice back
-- never moves stock or settles it (a warehouse-fulfilled one, or one never
-- settled but now covered, is refused); a cancelled invoice whose customer
-- already had part of it (sessions, therapy, vouchers, credit) cannot have
-- its money recorded as paid back in one amount; an open invoice with a line
-- refunded does not show the refund as owed in the list.
--
-- Disposable local database only; everything is rolled back. The migration is
-- applied inside this transaction, so run the file on its own:
--   psql -v ON_ERROR_STOP=1 -f scripts/invoice-actions/tests/refund-requests-and-refund-due.sql
-- On a local database that has drifted from production, pass a file that
-- installs production's functions (409's BEFORE versions and what they call),
-- run right after the begin below:
--   psql -v ON_ERROR_STOP=1 -v prelude=/path/to/prod_prelude.sql -f ...
-- Every name, phone, number and amount here is invented.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
\if :{?prelude}
\i :prelude
\endif

\ir ../../../supabase/409_refund_requests_refund_due_customer_order.sql

-- ===== 1. The migration re-runs as a no-op =====
create temp table t409_before as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5,
         coalesce(array_to_string(p.proacl, ','), '') as acl
    from pg_proc p where p.pronamespace = 'public'::regnamespace;
create temp table t409_idx_before as
  select indexname::text, indexdef from pg_indexes where schemaname = 'public';
\ir ../../../supabase/409_refund_requests_refund_due_customer_order.sql
do $$
declare v_diff text;
begin
  select string_agg(coalesce(a.fn, b.fn), ', ') into v_diff
    from t409_before a
    full join (select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5,
                      coalesce(array_to_string(p.proacl, ','), '') as acl
                 from pg_proc p where p.pronamespace = 'public'::regnamespace) b on b.fn = a.fn
   where a.fn is null or b.fn is null or a.md5 <> b.md5 or a.acl <> b.acl;
  if v_diff is not null then raise exception 'FAIL 1: a re-run changed %', v_diff; end if;
  if exists (select indexname::text, indexdef from pg_indexes where schemaname = 'public'
             except select * from t409_idx_before)
     or exists (select * from t409_idx_before
                except select indexname::text, indexdef from pg_indexes where schemaname = 'public') then
    raise exception 'FAIL 1: a re-run changed an index'; end if;
  raise notice 'PASS 1: a second run of 409 changes no function, grant or index';
end $$;

-- ===== 1b. A function at another version refuses, and nothing is kept =====
-- (psql prints the two refusals as ERROR lines; they are expected, and
-- checked below.)
savepoint t409_guard;
create or replace function public.customer_survey_overview(p_query text default null, p_filter text default 'all',
  p_limit integer default 50, p_offset integer default 0)
returns table(customer_id uuid, full_name text, phone text, email text, survey_id uuid, survey_no text, source text,
  remarks_condition text, remarks_recommendation text, submitted_at timestamptz, reviewed_at timestamptz,
  remark_count bigint, last_remark_at timestamptz, total_count bigint)
language sql stable security definer set search_path = public
as $f$ select null::uuid, null, null, null, null::uuid, null, null, null, null, null::timestamptz, null::timestamptz,
  0::bigint, null::timestamptz, 0::bigint where false $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/409_refund_requests_refund_due_customer_order.sql
\set ON_ERROR_STOP on
rollback to savepoint t409_guard;
release savepoint t409_guard;
select set_config('t409.refused_changed', :'LAST_ERROR_MESSAGE', true) as t409_kept \gset
savepoint t409_guard2;
create or replace function public.invoice_charge_total(p_invoice_id uuid) returns numeric
language sql stable security definer set search_path = public as $f$ select 0::numeric $f$;
\set ON_ERROR_STOP off
\ir ../../../supabase/409_refund_requests_refund_due_customer_order.sql
\set ON_ERROR_STOP on
rollback to savepoint t409_guard2;
release savepoint t409_guard2;
select set_config('t409.refused_relied', :'LAST_ERROR_MESSAGE', true) as t409_kept \gset
do $$
begin
  -- 409 is installed here already, so a patched function at a third text is
  -- neither its BEFORE nor its AFTER.
  if current_setting('t409.refused_changed') not like '409: public.customer_survey_overview(text,text,integer,integer) is not the version this was tested against%' then
    raise exception 'FAIL 1b: a function at another version was not refused: %', current_setting('t409.refused_changed'); end if;
  if current_setting('t409.refused_relied') not like '409: public.invoice_charge_total(uuid) is missing or not the version read on 9 Oct 2026%' then
    raise exception 'FAIL 1b: a relied-on function at another version was not refused: %', current_setting('t409.refused_relied'); end if;
  if exists (select indexname::text, indexdef from pg_indexes where schemaname = 'public'
             except select * from t409_idx_before) then
    raise exception 'FAIL 1b: a refused run kept an index'; end if;
  raise notice 'PASS 1b: a patched function at another version, or a relied-on one, refuses (naming it) and nothing is kept';
end $$;

-- ===== 2. Who may call what =====
do $$
declare v text;
begin
  if has_function_privilege('authenticated', 'public.request_invoice_action(uuid,text,boolean,text)', 'execute')
     or has_function_privilege('anon', 'public.request_invoice_action(uuid,text,boolean,text)', 'execute') then
    raise exception 'FAIL 2: the retired request_invoice_action is still a client endpoint'; end if;
  if not has_function_privilege('service_role', 'public.request_invoice_action(uuid,text,boolean,text)', 'execute') then
    raise exception 'FAIL 2: the service role lost request_invoice_action'; end if;
  -- The new helper is internal (339).
  if has_function_privilege('authenticated', 'public.cancelled_invoice_used_value(uuid)', 'execute')
     or has_function_privilege('anon', 'public.cancelled_invoice_used_value(uuid)', 'execute')
     or has_function_privilege('public', 'public.cancelled_invoice_used_value(uuid)', 'execute')
     or not has_function_privilege('service_role', 'public.cancelled_invoice_used_value(uuid)', 'execute') then
    raise exception 'FAIL 2: cancelled_invoice_used_value is not the service role''s alone'; end if;
  foreach v in array array['resolve_invoice_action_v2(uuid,boolean,text,text,jsonb,jsonb,boolean)',
                           'refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)',
                           'invoice_list_page(text,text,text,date,date,uuid,text,text,integer,integer)',
                           'search_customers(text,text,integer,integer,text,date,date)',
                           'customer_survey_overview(text,text,integer,integer)',
                           -- what staff use for a guided request
                           'request_invoice_action_v2(uuid,text,jsonb,text,text,uuid)',
                           'invoice_action_plan(uuid,text,jsonb)'] loop
    if not has_function_privilege('authenticated', 'public.' || v, 'execute')
       or has_function_privilege('anon', 'public.' || v, 'execute') then
      raise exception 'FAIL 2: public.% is not signed-in logins'' alone', v; end if;
  end loop;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
       and proname in ('resolve_invoice_action_v2', 'refund_invoice_recorded', 'invoice_list_page',
                       'search_customers', 'customer_survey_overview', 'request_invoice_action',
                       'cancelled_invoice_used_value')) <> 7 then
    raise exception 'FAIL 2: an overload of a 409 function exists'; end if;
  raise notice 'PASS 2: request_invoice_action and the new cancelled_invoice_used_value are the service role''s alone; the five patched functions and the guided request stay signed-in logins'' and none is callable signed out; no overloads';
end $$;

-- ===== Fixtures =====
create temp table t409(k text primary key, id uuid);
do $$
declare own uuid := gen_random_uuid(); stf uuid := gen_random_uuid(); st uuid; st2 uuid; c uuid; pm uuid; p uuid;
  v uuid; pb uuid;
begin
  insert into auth.users(id, email) values (own, 't409-own@tests.invalid'), (stf, 't409-stf@tests.invalid');
  insert into profiles(id, full_name, email, role) values
    (own, 'T409 Owner', 't409-own@tests.invalid', 'owner'), (stf, 'T409 Staff', 't409-stf@tests.invalid', 'staff');
  perform set_config('request.jwt.claim.sub', own::text, true);
  insert into stores(name, code, country_code) values ('T409 Store', 'T409S', 'SG') returning id into st;
  insert into stores(name, code, country_code) values ('T409 List Store', 'T409L', 'SG') returning id into st2;
  insert into user_store_assignments(user_id, store_id) values (stf, st), (stf, st2);
  insert into customers(full_name, phone) values ('T409 Buyer', '+6591400901') returning id into c;
  insert into payment_methods(name, is_active) values ('T409 PayNow', true) returning id into pm;
  insert into products(name, sku, product_type) values ('T409 Item', 'T409I', 'own') returning id into p;
  insert into store_inventory(store_id, product_id, current_qty) values (st, p, 100), (st2, p, 100);
  perform set_product_prices(st, p, 100, 100, 'available');
  perform set_product_prices(st2, p, 100, 100, 'available');
  insert into vouchers(name, code, qty_type, reward_eligible) values ('T409 Voucher', 'T409-V', 'limited', true) returning id into v;
  insert into voucher_store_stock(voucher_id, store_id, current_qty) values (v, st, 20), (v, st2, 20);
  insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (v, st, 20, true), (v, st2, 20, true);
  -- 140 paid: 100 paid credit, 40 bonus credit, two issued vouchers.
  insert into premium_bundles(name, customer_payment_amount, paid_credit_amount, bonus_credit_amount, free_voucher_qty, grants_reward)
    values ('T409 Bundle', 140, 100, 40, 2, true) returning id into pb;
  insert into premium_bundle_stores(bundle_id, store_id) values (pb, st), (pb, st2);
  insert into premium_bundle_vouchers(bundle_id, voucher_id) values (pb, v);
  insert into t409 values ('own', own), ('stf', stf), ('store', st), ('list_store', st2), ('customer', c),
    ('paynow', pm), ('product', p), ('voucher', v), ('bundle', pb);
end $$;

create function pg_temp.t409_id(p_k text) returns uuid language sql as $f$ select id from t409 where k = p_k $f$;
-- What a customer can use up: a S$30 session, a S$150 therapy package, a
-- S$40 sold voucher, a S$100 credit package; and a warehouse.
do $$
declare st uuid := pg_temp.t409_id('store'); ts uuid; tp uuid; sv uuid; cp uuid; wh uuid;
begin
  perform set_config('request.jwt.claim.sub', pg_temp.t409_id('own')::text, true);
  insert into therapy_services(service_code, name, standard_price, duration_minutes, is_active)
    values ('T409S30', 'T409 Session', 30, 30, true) returning id into ts;
  insert into therapy_service_stores(service_id, store_id) values (ts, st);
  insert into unlimited_therapy_packages(name, duration_months) values ('T409 Therapy 1m', 1) returning id into tp;
  insert into unlimited_therapy_store_prices(package_id, store_id, selling_price, available_at_store) values (tp, st, 150, true);
  insert into vouchers(name, code, voucher_kind, selling_price, qty_type) values ('T409 Gift 40', 'T409-G40', 'normal', 40, 'limited')
    returning id into sv;
  insert into voucher_store_stock(voucher_id, store_id, current_qty) values (sv, st, 20);
  insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (sv, st, 40, true);
  insert into credit_packages(name, customer_price, paid_credit_amount) values ('T409 Credit 100', 100, 100) returning id into cp;
  insert into warehouses(name, code) values ('T409 Warehouse', 'T409W') returning id into wh;
  insert into warehouse_inventory(warehouse_id, product_id, current_qty) values (wh, pg_temp.t409_id('product'), 50);
  insert into t409 values ('session', ts), ('therapy', tp), ('gift', sv), ('credit', cp), ('warehouse', wh);
end $$;
-- One line of `kind` (session, therapy, gift, credit), quantity q, paid `paid`.
create function pg_temp.t409_sale(p_kind text, p_qty int, p_paid numeric) returns uuid
language plpgsql as $f$
declare v_inv uuid; v_line jsonb;
begin
  v_line := case p_kind
    when 'session' then jsonb_build_object('kind', 'therapy', 'therapy_service_id', pg_temp.t409_id('session'), 'quantity', p_qty)
    when 'therapy' then jsonb_build_object('kind', 'therapy', 'therapy_package_id', pg_temp.t409_id('therapy'), 'quantity', p_qty)
    when 'gift' then jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.t409_id('gift'), 'quantity', p_qty)
    when 'credit' then jsonb_build_object('kind', 'credit_package', 'credit_package_id', pg_temp.t409_id('credit'), 'quantity', p_qty) end;
  v_inv := create_invoice(pg_temp.t409_id('store'), pg_temp.t409_id('customer'), null, jsonb_build_array(v_line));
  if p_paid > 0 then
    perform pay_invoice(v_inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t409_id('paynow'), 'amount', p_paid)));
  end if;
  return v_inv;
end $f$;
-- An invoice of one product line (quantity q at S$100) and, optionally, the
-- bundle; paid `paid` (0 = nothing).
create function pg_temp.t409_invoice(p_store text, p_qty int, p_bundle boolean, p_paid numeric) returns uuid
language plpgsql as $f$
declare v_inv uuid; v_items jsonb;
begin
  v_items := jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.t409_id('product'), 'quantity', p_qty));
  if p_bundle then
    v_items := v_items || jsonb_build_array(jsonb_build_object('kind', 'premium_bundle', 'premium_bundle_id', pg_temp.t409_id('bundle'),
      'quantity', 1, 'voucher_selection', jsonb_build_array(jsonb_build_object('voucher_id', pg_temp.t409_id('voucher'), 'quantity', 2))));
  end if;
  v_inv := create_invoice_with_details(pg_temp.t409_id(p_store), pg_temp.t409_id('customer'), v_items,
    jsonb_build_object('business_date', sg_today()::text));
  if p_paid > 0 then
    perform record_invoice_payment(v_inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t409_id('paynow'),
      'amount', p_paid)), gen_random_uuid());
  end if;
  return v_inv;
end $f$;
-- Everything a "became paid" trigger could add again, for one invoice.
create function pg_temp.t409_effects(p_inv uuid) returns jsonb language sql as $f$
  select jsonb_build_object(
    'invoice', (select jsonb_build_object('status', status, 'paid_amount', paid_amount, 'total', total_amount)
                  from invoices where id = p_inv),
    'movements', (select count(*) from stock_movements where invoice_id = p_inv),
    'shelf', (select sum(current_qty) from store_inventory where product_id = pg_temp.t409_id('product')),
    'voucher_stock', (select sum(current_qty) from voucher_store_stock where voucher_id = pg_temp.t409_id('voucher')),
    'benefits', (select count(*) from invoice_benefit_values where invoice_id = p_inv),
    'lots', (select jsonb_build_object('n', count(*), 'remaining', coalesce(sum(l.remaining_amount), 0))
               from customer_credit_lots l where l.customer_id = pg_temp.t409_id('customer')),
    'ledger', (select count(*) from customer_credit_ledger where customer_id = pg_temp.t409_id('customer')),
    'reward_vouchers', (select jsonb_build_object('n', count(*), 'held', coalesce(sum(quantity) filter (where status = 'held'), 0))
                          from customer_reward_vouchers where customer_id = pg_temp.t409_id('customer')),
    'commissions', (select count(*) from commissions where invoice_id = p_inv),
    'refunds', (select count(*) from invoice_refunds where invoice_id = p_inv),
    'payments', (select count(*) from invoice_payments where invoice_id = p_inv))
$f$;

-- ===== 3. A request raised the old way, rejected: the invoice goes back to Paid =====
do $$
declare inv uuid; req uuid; res jsonb; before jsonb; after jsonb;
begin
  perform set_config('request.jwt.claim.sub', pg_temp.t409_id('own')::text, true);
  inv := pg_temp.t409_invoice('store', 2, true, 340);
  if (select status from invoices where id = inv) <> 'paid' then
    raise exception 'Fixture: the product-and-bundle invoice is not paid'; end if;
  if (select count(*) from invoice_benefit_values where invoice_id = inv) < 3 then
    raise exception 'Fixture: the bundle did not issue its credit and vouchers'; end if;
  before := pg_temp.t409_effects(inv);

  -- What the old staff button did (the function is no longer a client
  -- endpoint; this connection is not a client role).
  perform set_config('request.jwt.claim.sub', pg_temp.t409_id('stf')::text, true);
  req := request_invoice_action(inv, 'invoice_refund', true, 'Customer changed their mind');
  if (select status from invoices where id = inv) <> 'refund_requested' then
    raise exception 'Fixture: the old request did not move the invoice to refund_requested'; end if;
  -- Staff cannot reject it.
  begin
    perform resolve_invoice_action_v2(req, false, 'Staff rejecting');
    raise exception 'FAIL 3: staff rejected an invoice request';
  exception when others then
    if sqlerrm not like 'Only an Owner or Manager%' then raise; end if;
  end;

  perform set_config('request.jwt.claim.sub', pg_temp.t409_id('own')::text, true);
  res := resolve_invoice_action_v2(req, false, 'Outside our refund terms');
  if res->>'status' <> 'rejected' or res->>'invoice_status_restored' is distinct from 'paid' then
    raise exception 'FAIL 3: rejection returned %', res; end if;
  if (select status from approval_requests where id = req) <> 'rejected' then
    raise exception 'FAIL 3: the request is not rejected'; end if;
  after := pg_temp.t409_effects(inv);
  if after <> before then
    raise exception 'FAIL 3: rejecting moved more than the status: before % after %', before, after; end if;
  if not exists (select 1 from audit_logs a where a.table_name = 'invoices' and a.record_id = inv
                   and a.action = 'request_rejected_status_restored'
                   and a.old_data->>'status' = 'refund_requested' and a.new_data->>'status' = 'paid'
                   and a.new_data->>'request_id' = req::text) then
    raise exception 'FAIL 3: the invoice''s history does not say its status was put back'; end if;
  if not exists (select 1 from audit_logs a where a.table_name = 'approval_requests' and a.record_id = req
                   and a.action = 'invoice_action_rejected' and a.new_data->>'invoice_status_restored' = 'paid') then
    raise exception 'FAIL 3: the rejection''s history does not say what it restored'; end if;
  -- Back to paid, the invoice is in the Paid filter again.
  if not exists (select 1 from jsonb_array_elements(invoice_list_page(p_status => 'paid', p_store_id => pg_temp.t409_id('store'),
                   p_limit => 200)->'rows') x where (x->>'id')::uuid = inv) then
    raise exception 'FAIL 3: the restored invoice is not in the Paid filter'; end if;
  -- And a second rejection of the same request changes nothing.
  res := resolve_invoice_action_v2(req, false, 'Again');
  if not coalesce((res->>'already_resolved')::boolean, false) or pg_temp.t409_effects(inv) <> before then
    raise exception 'FAIL 3: a repeated rejection did something: %', res; end if;
  raise notice 'PASS 3: an old-style refund request, rejected by an Owner, puts the invoice back to paid (it is in the Paid filter again) with no stock, credit, voucher, commission, payment or refund moved, and says so in both histories; staff cannot reject; a repeat does nothing';
end $$;

-- ===== 4. The old cancellation request: part-paid and unpaid go back as their payments say =====
do $$
declare inv uuid; inv2 uuid; req uuid; res jsonb; before jsonb;
begin
  perform set_config('request.jwt.claim.sub', pg_temp.t409_id('own')::text, true);
  inv := pg_temp.t409_invoice('store', 3, false, 120);
  inv2 := pg_temp.t409_invoice('store', 1, false, 0);
  if (select status from invoices where id = inv) <> 'partially_paid' or (select status from invoices where id = inv2) <> 'unpaid' then
    raise exception 'Fixture: expected a part-paid and an unpaid invoice'; end if;
  before := pg_temp.t409_effects(inv);
  perform set_config('request.jwt.claim.sub', pg_temp.t409_id('stf')::text, true);
  req := request_invoice_action(inv, 'invoice_cancel', true, 'Customer wants to stop');
  perform set_config('request.jwt.claim.sub', pg_temp.t409_id('own')::text, true);
  res := resolve_invoice_action_v2(req, false, 'Balance will be paid');
  if res->>'invoice_status_restored' is distinct from 'partially_paid'
     or (select status from invoices where id = inv) <> 'partially_paid' or pg_temp.t409_effects(inv) <> before then
    raise exception 'FAIL 4: a rejected cancellation of a part-paid invoice left %, %', res, pg_temp.t409_effects(inv); end if;

  before := pg_temp.t409_effects(inv2);
  perform set_config('request.jwt.claim.sub', pg_temp.t409_id('stf')::text, true);
  req := request_invoice_action(inv2, 'invoice_cancel', true, 'Raised in error');
  perform set_config('request.jwt.claim.sub', pg_temp.t409_id('own')::text, true);
  res := resolve_invoice_action_v2(req, false, 'Keep it');
  if res->>'invoice_status_restored' is distinct from 'unpaid'
     or (select status from invoices where id = inv2) <> 'unpaid' or pg_temp.t409_effects(inv2) <> before then
    raise exception 'FAIL 4: a rejected cancellation of an unpaid invoice left %', res; end if;
  raise notice 'PASS 4: a rejected old-style cancellation puts a part-paid invoice back to partially_paid and an unpaid one to unpaid, nothing else moved';
end $$;

-- ===== 4b. Putting it back never moves stock and never settles =====
do $$
declare inv uuid; req uuid; res jsonb; w0 int; s0 int; e text; before jsonb;
begin
  perform set_config('request.jwt.claim.sub', pg_temp.t409_id('own')::text, true);
  -- (D) Fulfilled from a warehouse: paying took the goods from the warehouse
  -- and gave the store's back; putting it back to paid would do that again.
  inv := create_invoice(pg_temp.t409_id('store'), pg_temp.t409_id('customer'), null, jsonb_build_array(
    jsonb_build_object('kind', 'product', 'product_id', pg_temp.t409_id('product'), 'quantity', 2)));
  update invoices set fulfil_warehouse_id = pg_temp.t409_id('warehouse') where id = inv;
  perform pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t409_id('paynow'), 'amount', 200)));
  if (select status from invoices where id = inv) <> 'paid'
     or (select current_qty from warehouse_inventory where warehouse_id = pg_temp.t409_id('warehouse')) <> 48 then
    raise exception 'Fixture: the warehouse-fulfilled sale is not paid from the warehouse'; end if;
  perform set_config('request.jwt.claim.sub', pg_temp.t409_id('stf')::text, true);
  req := request_invoice_action(inv, 'invoice_refund', true, 'Changed mind');
  perform set_config('request.jwt.claim.sub', pg_temp.t409_id('own')::text, true);
  select current_qty into w0 from warehouse_inventory where warehouse_id = pg_temp.t409_id('warehouse');
  select current_qty into s0 from store_inventory where store_id = pg_temp.t409_id('store') and product_id = pg_temp.t409_id('product');
  before := pg_temp.t409_effects(inv);
  begin
    res := resolve_invoice_action_v2(req, false, 'Not within terms');
    raise exception 'FAIL 4b: rejecting put a warehouse-fulfilled invoice back to paid: %, warehouse %', res,
      (select current_qty from warehouse_inventory where warehouse_id = pg_temp.t409_id('warehouse'));
  exception when others then
    if sqlerrm not like 'Rejecting this request would put % back to paid, which takes its goods from the fulfilling warehouse a second time. Nothing was changed%' then raise; end if;
  end;
  if (select current_qty from warehouse_inventory where warehouse_id = pg_temp.t409_id('warehouse')) <> w0
     or (select current_qty from store_inventory where store_id = pg_temp.t409_id('store') and product_id = pg_temp.t409_id('product')) <> s0
     or pg_temp.t409_effects(inv) <> before
     or (select status from approval_requests where id = req) <> 'pending' then
    raise exception 'FAIL 4b: the refused rejection changed something'; end if;

  -- (E) An FOC invoice never confirmed (unpaid, S$0): its old cancellation
  -- request, rejected, leaves it unpaid; confirming it is confirm_foc_invoice's.
  inv := create_invoice(pg_temp.t409_id('store'), pg_temp.t409_id('customer'), null, jsonb_build_array(
    jsonb_build_object('kind', 'product', 'product_id', pg_temp.t409_id('product'), 'quantity', 1, 'foc_quantity', 1, 'foc_reason', 'Gift')));
  if (select (status, total_amount, has_foc, locked_at is null) from invoices where id = inv)
     is distinct from ('unpaid'::invoice_status, 0::numeric(12,2), true, true) then
    raise exception 'Fixture: expected an unconfirmed S$0 FOC invoice, got %', (select to_jsonb(i) - 'notes' from invoices i where id = inv); end if;
  before := pg_temp.t409_effects(inv);
  perform set_config('request.jwt.claim.sub', pg_temp.t409_id('stf')::text, true);
  req := request_invoice_action(inv, 'invoice_cancel', true, 'Wrong customer');
  perform set_config('request.jwt.claim.sub', pg_temp.t409_id('own')::text, true);
  res := resolve_invoice_action_v2(req, false, 'Keep it');
  if res->>'invoice_status_restored' is distinct from 'unpaid' or pg_temp.t409_effects(inv) <> before
     or (select locked_at from invoices where id = inv) is not null then
    raise exception 'FAIL 4b: the unconfirmed FOC invoice came back as % (locked %), %', res->>'invoice_status_restored',
      (select locked_at is not null from invoices where id = inv), pg_temp.t409_effects(inv); end if;

  -- (U) Never settled, but its payments cover what it now charges: putting it
  -- back would settle it (stock, vouchers, commission) without a payment's
  -- checks, so it is refused. (The state is made directly: the total is cut
  -- to what was paid while the request waited.)
  inv := pg_temp.t409_invoice('store', 1, false, 40);
  perform set_config('request.jwt.claim.sub', pg_temp.t409_id('stf')::text, true);
  req := request_invoice_action(inv, 'invoice_cancel', true, 'Customer wants to stop');
  perform set_config('request.jwt.claim.sub', pg_temp.t409_id('own')::text, true);
  update invoices set total_amount = 40 where id = inv;
  before := pg_temp.t409_effects(inv);
  begin
    res := resolve_invoice_action_v2(req, false, 'No');
    raise exception 'FAIL 4b: rejecting settled an invoice that was never settled: %', res;
  exception when others then
    if sqlerrm not like 'Rejecting this request would settle %, which was not settled when the request was raised%' then raise; end if;
  end;
  if pg_temp.t409_effects(inv) <> before or (select status from invoices where id = inv) <> 'cancellation_requested'
     or (select status from approval_requests where id = req) <> 'pending' then
    raise exception 'FAIL 4b: the refused rejection changed something'; end if;
  raise notice 'PASS 4b: rejecting an old-style request never moves stock or settles: a warehouse-fulfilled invoice is refused (warehouse, shelf, request unchanged), an unconfirmed FOC invoice goes back to unpaid unlocked with no stock taken, and one never settled but now covered is refused';
end $$;

-- ===== 5. The guided request (what staff now use): nothing moves until approval =====
do $$
declare inv uuid; inv2 uuid; req jsonb; res jsonb; before jsonb;
begin
  perform set_config('request.jwt.claim.sub', pg_temp.t409_id('own')::text, true);
  inv := pg_temp.t409_invoice('store', 1, false, 100);
  inv2 := pg_temp.t409_invoice('store', 2, false, 50);
  before := pg_temp.t409_effects(inv);
  perform set_config('request.jwt.claim.sub', pg_temp.t409_id('stf')::text, true);
  req := request_invoice_action_v2(inv, 'refund_full', '[]'::jsonb, 'Customer returned it', null, gen_random_uuid());
  if req->>'status' <> 'pending' or pg_temp.t409_effects(inv) <> before then
    raise exception 'FAIL 5: a staff guided request changed the invoice: %', pg_temp.t409_effects(inv); end if;
  perform set_config('request.jwt.claim.sub', pg_temp.t409_id('own')::text, true);
  res := resolve_invoice_action_v2((req->>'request_id')::uuid, false, 'Not this time');
  if res->>'status' <> 'rejected' or res ? 'invoice_status_restored' and res->>'invoice_status_restored' is not null
     or pg_temp.t409_effects(inv) <> before then
    raise exception 'FAIL 5: rejecting a guided request changed the invoice: %, %', res, pg_temp.t409_effects(inv); end if;
  -- Staff can ask to cancel a part-paid invoice too (the old button could not).
  perform set_config('request.jwt.claim.sub', pg_temp.t409_id('stf')::text, true);
  req := request_invoice_action_v2(inv2, 'cancel', '[]'::jsonb, 'Customer is not continuing', null, gen_random_uuid());
  if req->>'status' <> 'pending' or (select status from invoices where id = inv2) <> 'partially_paid' then
    raise exception 'FAIL 5: a staff cancellation request on a part-paid invoice: %', req; end if;
  if (select count(*) from approval_requests where related_record_id = inv2 and status = 'pending'
        and payload->'plan' is not null) <> 1 then
    raise exception 'FAIL 5: the request carries no plan, so it could not be approved'; end if;
  perform set_config('request.jwt.claim.sub', pg_temp.t409_id('own')::text, true);
  raise notice 'PASS 5: staff raise refund and cancellation requests (part-paid included) through the guided flow with a plan; rejecting one changes nothing on the invoice';
end $$;

-- ===== 6. The refund still due after a cancellation can be recorded =====
do $$
declare inv uuid; pay uuid; rid uuid := gen_random_uuid(); res jsonb; pos jsonb; n int; mv jsonb;
  inv2 uuid; pay2 uuid; inv3 uuid; pay3 uuid; inv4 uuid; plan jsonb; lines jsonb; ledger_before int;
begin
  perform set_config('request.jwt.claim.sub', pg_temp.t409_id('own')::text, true);
  -- Like INV-2026-0317: a premium bundle, part-paid, cancelled without the
  -- money going back. Its line has nothing to refund through.
  inv := create_invoice_with_details(pg_temp.t409_id('store'), pg_temp.t409_id('customer'),
    jsonb_build_array(jsonb_build_object('kind', 'premium_bundle', 'premium_bundle_id', pg_temp.t409_id('bundle'), 'quantity', 1,
      'voucher_selection', jsonb_build_array(jsonb_build_object('voucher_id', pg_temp.t409_id('voucher'), 'quantity', 2)))),
    jsonb_build_object('business_date', sg_today()::text));
  perform record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t409_id('paynow'),
    'amount', 40)), gen_random_uuid());
  select id into pay from invoice_payments where invoice_id = inv;
  perform cancel_invoice_recorded(inv, 'Customer withdrew', gen_random_uuid());
  pos := invoice_financial_position(inv);
  if pos->>'status' <> 'cancelled' or (pos->>'refund_due')::numeric <> 40 then
    raise exception 'Fixture: expected a cancelled bundle with S$40 due, got %', pos; end if;
  if (invoice_action_plan(inv, 'cancel')->>'refund_due')::numeric <> 0 then
    raise exception 'Fixture: the bundle line was expected to have nothing to refund through'; end if;
  ledger_before := (select count(*) from customer_credit_ledger where customer_id = pg_temp.t409_id('customer'));

  -- Staff cannot record it.
  perform set_config('request.jwt.claim.sub', pg_temp.t409_id('stf')::text, true);
  begin
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', null, 'amount', 40)),
      jsonb_build_array(jsonb_build_object('payment_id', pay, 'amount', 40)), '[]'::jsonb, 'Paid back', gen_random_uuid());
    raise exception 'FAIL 6: staff recorded a refund';
  exception when others then
    if sqlerrm not like 'Only an Owner or Manager%' then raise; end if;
  end;
  perform set_config('request.jwt.claim.sub', pg_temp.t409_id('own')::text, true);
  -- Not more than is due.
  begin
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', null, 'amount', 40.01)),
      jsonb_build_array(jsonb_build_object('payment_id', pay, 'amount', 40.01)), '[]'::jsonb, 'Paid back', gen_random_uuid());
    raise exception 'FAIL 6: more than the refund due was recorded';
  exception when others then
    if sqlerrm not like 'Amount exceeds%' then raise; end if;
  end;
  -- The refund due, recorded.
  res := refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', null, 'amount', 40)),
    jsonb_build_array(jsonb_build_object('payment_id', pay, 'amount', 40)), '[]'::jsonb, 'Paid back by bank transfer', rid);
  pos := invoice_financial_position(inv);
  if (res->>'refunded_amount')::numeric <> 40 or pos->>'status' <> 'cancelled' or (pos->>'refund_due')::numeric <> 0
     or (pos->>'refunded')::numeric <> 40 or (pos->>'net_received')::numeric <> 0 then
    raise exception 'FAIL 6: after recording the refund due: %, %', res, pos; end if;
  if (select paid_amount from invoices where id = inv) <> 0 then
    raise exception 'FAIL 6: the invoice still shows money held'; end if;
  if (select count(*) from invoice_refunds where invoice_id = inv and request_id = rid and payment_id = pay and amount = 40) <> 1 then
    raise exception 'FAIL 6: no refund row against the original payment'; end if;
  if not exists (select 1 from audit_logs where table_name = 'invoices' and record_id = inv and action = 'allocated_refund') then
    raise exception 'FAIL 6: the refund is not in the invoice''s history'; end if;
  if (select count(*) from customer_credit_ledger where customer_id = pg_temp.t409_id('customer')) <> ledger_before then
    raise exception 'FAIL 6: recording the refund due moved credit'; end if;
  -- Once: the same request replays, other details under it refuse, and a new
  -- request finds nothing left.
  res := refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', null, 'amount', 40)),
    jsonb_build_array(jsonb_build_object('payment_id', pay, 'amount', 40)), '[]'::jsonb, 'Paid back by bank transfer', rid);
  if not coalesce((res->>'replayed')::boolean, false) or (select count(*) from invoice_refunds where invoice_id = inv) <> 1 then
    raise exception 'FAIL 6: a repeat recorded it twice: %', res; end if;
  begin
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', null, 'amount', 30)),
      jsonb_build_array(jsonb_build_object('payment_id', pay, 'amount', 30)), '[]'::jsonb, 'Paid back by bank transfer', rid);
    raise exception 'FAIL 6: one request ID recorded two different refunds';
  exception when others then
    if sqlerrm not like '%already used for different details%' then raise; end if;
  end;
  begin
    perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', null, 'amount', 1)),
      jsonb_build_array(jsonb_build_object('payment_id', pay, 'amount', 1)), '[]'::jsonb, 'Again', gen_random_uuid());
    raise exception 'FAIL 6: a second refund was recorded with nothing due';
  exception when others then
    if sqlerrm not like 'Amount exceeds%' then raise; end if;
  end;

  -- A fully paid product sale, cancelled with the money still held: the
  -- stock came back with the cancellation, and the whole S$200 is due.
  inv2 := pg_temp.t409_invoice('store', 2, false, 200);
  select id into pay2 from invoice_payments where invoice_id = inv2;
  perform cancel_invoice_recorded(inv2, 'Order cancelled', gen_random_uuid());
  n := (select count(*) from stock_movements where invoice_id = inv2);
  res := refund_invoice_recorded(inv2, jsonb_build_array(jsonb_build_object('invoice_item_id', null, 'amount', 200)),
    jsonb_build_array(jsonb_build_object('payment_id', pay2, 'amount', 200)), '[]'::jsonb, 'Refunded at the counter', gen_random_uuid());
  if (invoice_financial_position(inv2)->>'refund_due')::numeric <> 0
     or (select count(*) from stock_movements where invoice_id = inv2) <> n then
    raise exception 'FAIL 6: the cancelled product sale: %', invoice_financial_position(inv2); end if;

  -- Part of it: S$50 of a S$100 cancelled sale, then the rest.
  inv3 := pg_temp.t409_invoice('store', 1, false, 100);
  select id into pay3 from invoice_payments where invoice_id = inv3;
  perform cancel_invoice_recorded(inv3, 'Order cancelled', gen_random_uuid());
  perform refund_invoice_recorded(inv3, jsonb_build_array(jsonb_build_object('invoice_item_id', null, 'amount', 50)),
    jsonb_build_array(jsonb_build_object('payment_id', pay3, 'amount', 50)), '[]'::jsonb, 'First half back', gen_random_uuid());
  if (invoice_financial_position(inv3)->>'refund_due')::numeric <> 50 then
    raise exception 'FAIL 6: after half: %', invoice_financial_position(inv3); end if;
  perform refund_invoice_recorded(inv3, jsonb_build_array(jsonb_build_object('invoice_item_id', null, 'amount', 50)),
    jsonb_build_array(jsonb_build_object('payment_id', pay3, 'amount', 50)), '[]'::jsonb, 'Second half back', gen_random_uuid());
  if (invoice_financial_position(inv3)->>'refund_due')::numeric <> 0 then
    raise exception 'FAIL 6: after both halves: %', invoice_financial_position(inv3); end if;

  -- An open invoice keeps the old ceiling: nothing paid above its total.
  begin
    perform refund_invoice_recorded(inv3, jsonb_build_array(jsonb_build_object('invoice_item_id', null, 'amount', 1)),
      jsonb_build_array(jsonb_build_object('payment_id', pay3, 'amount', 1)), '[]'::jsonb, 'x', gen_random_uuid());
    raise exception 'FAIL 6: refunded past nothing due';
  exception when others then
    if sqlerrm not like 'Amount exceeds%' and sqlerrm not like 'Refund exceeds%' then raise; end if;
  end;
  inv4 := pg_temp.t409_invoice('store', 1, false, 60);
  begin
    perform refund_invoice_recorded(inv4, jsonb_build_array(jsonb_build_object('invoice_item_id', null, 'amount', 10)),
      jsonb_build_array(jsonb_build_object('payment_id', (select id from invoice_payments where invoice_id = inv4), 'amount', 10)),
      '[]'::jsonb, 'Not cancelled', gen_random_uuid());
    raise exception 'FAIL 6: an unallocated refund on an open part-paid invoice was accepted';
  exception when others then
    if sqlerrm not like 'Amount exceeds the correction refund due%' then raise; end if;
  end;

  -- A cancelled bundle whose credit was issued still goes back through its
  -- benefits (the page offers that when this line is refused).
  inv4 := pg_temp.t409_invoice('store', 1, true, 240);
  perform cancel_invoice_recorded(inv4, 'Whole order cancelled', gen_random_uuid());
  begin
    perform refund_invoice_recorded(inv4, jsonb_build_array(jsonb_build_object('invoice_item_id', null, 'amount', 240)),
      jsonb_build_array(jsonb_build_object('payment_id', (select id from invoice_payments where invoice_id = inv4), 'amount', 240)),
      '[]'::jsonb, 'Paid back', gen_random_uuid());
    raise exception 'FAIL 6: issued credit was cashed out without its benefits';
  exception when others then
    if sqlerrm not like 'Allocate a correction refund to the original unused purchased benefits%' then raise; end if;
  end;
  plan := invoice_action_plan(inv4, 'cancel');
  select jsonb_agg(jsonb_build_object('invoice_item_id', l->>'invoice_item_id', 'amount', (l->>'amount')::numeric,
           'benefits', (select coalesce(jsonb_agg(jsonb_build_object('benefit_id', b->>'benefit_id', 'amount', (b->>'amount')::numeric)), '[]')
                          from jsonb_array_elements(l->'benefits') b)))
    into lines from jsonb_array_elements(plan->'lines') l where (l->>'amount')::numeric > 0;
  if (plan->>'refund_due')::numeric <> 240 then
    raise exception 'Fixture: the cancelled bundle-and-product plan says % due', plan->>'refund_due'; end if;
  perform refund_invoice_recorded(inv4, lines,
    (select jsonb_agg(jsonb_build_object('payment_id', s->>'payment_id', 'amount', (s->>'amount')::numeric)) from jsonb_array_elements(plan->'sources') s),
    '[]'::jsonb, 'Paid back line by line', gen_random_uuid());
  if (invoice_financial_position(inv4)->>'refund_due')::numeric <> 0 then
    raise exception 'FAIL 6: the itemised refund of a cancelled bundle left %', invoice_financial_position(inv4); end if;
  raise notice 'PASS 6: the refund due on a cancelled invoice (a part-paid bundle like INV-2026-0317, a product sale, in two parts) is recorded by an Owner or Manager against the original payment, not more than is due, once (a repeat replays, other details refuse), audited, moving no stock or credit; staff are refused; an open invoice keeps the old ceiling; issued credit still goes back through its benefits';
end $$;

-- ===== 6b. A cancelled invoice whose customer already had part of it =====
-- The cancellation kept what was used (the guided cancel leaves it out of its
-- refund due), so the money still held is not all owed back: the single line
-- is refused, naming what was used, and nothing is recorded.
create function pg_temp.t409_itemless(p_inv uuid, p_amount numeric) returns text language plpgsql as $f$
begin
  perform refund_invoice_recorded(p_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', null, 'amount', p_amount)),
    jsonb_build_array(jsonb_build_object('payment_id',
      (select id from invoice_payments where invoice_id = p_inv and entry_kind = 'receipt' order by created_at limit 1), 'amount', p_amount)),
    '[]'::jsonb, 'Paid back', gen_random_uuid());
  return 'recorded';
exception when others then return sqlerrm;
end $f$;
do $$
declare inv uuid; plan jsonb; res jsonb; req uuid; msg text; lot uuid;
begin
  perform set_config('request.jwt.claim.sub', pg_temp.t409_id('own')::text, true);

  -- (B) Three S$30 sessions, one delivered, cancelled through the guided flow
  -- with the override and the money not yet back: the plan said S$60 due, the
  -- invoice holds S$90.
  inv := pg_temp.t409_sale('session', 3, 90);
  update customer_therapy_sessions set quantity_used = 1 where invoice_id = inv and is_current;
  plan := invoice_action_plan(inv, 'cancel', '[]');
  req := (request_invoice_action_v2(inv, 'cancel', '[]', 'Customer moving away', null, gen_random_uuid())->>'request_id')::uuid;
  res := resolve_invoice_action_v2(req, true, 'Cancel; money later', plan->>'plan_hash',
    jsonb_build_array(jsonb_build_object('code', 'session_used', 'reason', 'One session delivered')), null, false);
  if (invoice_financial_position(inv)->>'status') <> 'cancelled' or (plan->>'refund_due')::numeric <> 60
     or (invoice_financial_position(inv)->>'refund_due')::numeric <> 90 then
    raise exception 'Fixture B: %, plan due %', invoice_financial_position(inv), plan->>'refund_due'; end if;
  if cancelled_invoice_used_value(inv) <> array['session_used'] then
    raise exception 'FAIL 6b: B used value %', cancelled_invoice_used_value(inv); end if;
  msg := pg_temp.t409_itemless(inv, 90);
  if msg not like 'Part of what % sold has been used (sessions delivered), so not all the money it still holds is owed back%' then
    raise exception 'FAIL 6b: the delivered session''s S$90 was not refused: %', msg; end if;
  if pg_temp.t409_itemless(inv, 30) not like 'Part of what %' or exists (select 1 from invoice_refunds where invoice_id = inv) then
    raise exception 'FAIL 6b: part of it was recorded'; end if;

  -- (B2) The same, with the reviewed S$60 recorded at approval: the S$30 left
  -- is the delivered session, not a refund still due.
  inv := pg_temp.t409_sale('session', 3, 90);
  update customer_therapy_sessions set quantity_used = 1 where invoice_id = inv and is_current;
  plan := invoice_action_plan(inv, 'cancel', '[]');
  req := (request_invoice_action_v2(inv, 'cancel', '[]', 'Customer moving away', null, gen_random_uuid())->>'request_id')::uuid;
  res := resolve_invoice_action_v2(req, true, 'Cancel and refund the rest', plan->>'plan_hash',
    jsonb_build_array(jsonb_build_object('code', 'session_used', 'reason', 'One session delivered')), null, true);
  if (invoice_financial_position(inv)->>'net_received')::numeric <> 30 then
    raise exception 'Fixture B2: %', invoice_financial_position(inv); end if;
  if pg_temp.t409_itemless(inv, 30) not like 'Part of what % (sessions delivered)%'
     or (select count(*) from invoice_refunds where invoice_id = inv) <> 1 then
    raise exception 'FAIL 6b: the delivered session was refunded after the reviewed refund'; end if;

  -- Therapy started.
  inv := pg_temp.t409_sale('therapy', 1, 150);
  update purchased_therapy_entitlements set status = 'active', activation_date = sg_today()
   where invoice_item_id in (select id from invoice_items where invoice_id = inv);
  perform cancel_invoice_recorded(inv, 'Cancelled after starting', gen_random_uuid());
  if cancelled_invoice_used_value(inv) <> array['therapy_activated'] then
    raise exception 'FAIL 6b: therapy used value %', cancelled_invoice_used_value(inv); end if;
  msg := pg_temp.t409_itemless(inv, 150);
  if msg not like 'Part of what % (therapy started or its vouchers collected)%' then
    raise exception 'FAIL 6b: started therapy was not refused: %', msg; end if;

  -- Sold vouchers redeemed.
  inv := pg_temp.t409_sale('gift', 2, 80);
  update customer_reward_vouchers set status = 'redeemed'
   where id in (select reward_voucher_id from invoice_benefit_values where invoice_id = inv);
  perform cancel_invoice_recorded(inv, 'Cancelled after use', gen_random_uuid());
  if cancelled_invoice_used_value(inv) <> array['voucher_redeemed'] then
    raise exception 'FAIL 6b: voucher used value %', cancelled_invoice_used_value(inv); end if;
  msg := pg_temp.t409_itemless(inv, 80);
  if msg not like 'Part of what % (vouchers redeemed)%' then
    raise exception 'FAIL 6b: redeemed vouchers were not refused: %', msg; end if;

  -- A part-paid credit package: S$40 paid released S$40 of credit, S$10 of it
  -- spent. The cancellation takes back the S$30 unspent; the S$10 stays spent.
  inv := pg_temp.t409_sale('credit', 1, 40);
  select pl.lot_id into lot from credit_package_progress_lots pl where pl.invoice_id = inv and pl.released_amount > 0;
  if lot is null then raise exception 'Fixture: the part-paid credit package released no credit'; end if;
  update customer_credit_lots set remaining_amount = remaining_amount - 10 where id = lot;
  perform cancel_invoice_recorded(inv, 'Cancelled after spending', gen_random_uuid());
  if cancelled_invoice_used_value(inv) <> array['credit_used'] then
    raise exception 'FAIL 6b: released credit used value %', cancelled_invoice_used_value(inv); end if;
  msg := pg_temp.t409_itemless(inv, 30);
  if msg not like 'Part of what % (credit spent)%' then
    raise exception 'FAIL 6b: spent released credit was not refused: %', msg; end if;
  -- And with nothing spent (INV-2026-0317's case: everything released was
  -- taken back), the S$40 held is recordable.
  inv := pg_temp.t409_sale('credit', 1, 40);
  perform cancel_invoice_recorded(inv, 'Cancelled unused', gen_random_uuid());
  if cardinality(cancelled_invoice_used_value(inv)) <> 0 then
    raise exception 'FAIL 6b: nothing was used but %', cancelled_invoice_used_value(inv); end if;
  msg := pg_temp.t409_itemless(inv, 40);
  if msg <> 'recorded' or (invoice_financial_position(inv)->>'refund_due')::numeric <> 0 then
    raise exception 'FAIL 6b: the unused part-paid package''s S$40 was not recorded: %', msg; end if;

  -- Credit issued in full and partly spent: refused already (through its
  -- benefits), and the helper says what was used.
  inv := pg_temp.t409_sale('credit', 1, 100);
  update customer_credit_lots set remaining_amount = remaining_amount - 25
   where id in (select lot_id from invoice_benefit_values where invoice_id = inv and lot_id is not null);
  perform cancel_invoice_recorded(inv, 'Cancelled after spending', gen_random_uuid());
  if cancelled_invoice_used_value(inv) <> array['credit_used'] then
    raise exception 'FAIL 6b: issued credit used value %', cancelled_invoice_used_value(inv); end if;
  if pg_temp.t409_itemless(inv, 75) not like 'Allocate a correction refund to the original unused purchased benefits%' then
    raise exception 'FAIL 6b: issued credit was cashed out'; end if;
  raise notice 'PASS 6b: a cancelled invoice whose customer already had part of it (a delivered session, before or after the reviewed refund; started therapy; redeemed vouchers; spent released or issued credit) cannot have its money recorded as paid back in one amount, and the refusal names what was used; with nothing spent (INV-2026-0317''s case) it can';
end $$;

-- ===== 7. The list: nothing outstanding on a cancelled, refunded or FOC invoice =====
do $$
declare inv_unpaid uuid; inv_part uuid; inv_cancel uuid; inv_refund uuid; it uuid; pay uuid; mv jsonb;
  page jsonb; row jsonb; ord text[];
begin
  perform set_config('request.jwt.claim.sub', pg_temp.t409_id('own')::text, true);
  inv_unpaid := pg_temp.t409_invoice('list_store', 1, false, 0);           -- owes 100
  inv_part := pg_temp.t409_invoice('list_store', 3, false, 120);           -- owes 180
  inv_cancel := pg_temp.t409_invoice('list_store', 5, false, 40);          -- 500, 40 held, cancelled
  perform cancel_invoice_recorded(inv_cancel, 'Cancelled', gen_random_uuid());
  inv_refund := pg_temp.t409_invoice('list_store', 2, false, 200);         -- 200, refunded in full
  select id into it from invoice_items where invoice_id = inv_refund;
  select id into pay from invoice_payments where invoice_id = inv_refund;
  select jsonb_agg(jsonb_build_object('movement_id', id, 'sellable_quantity', quantity)) into mv
    from stock_movements where invoice_id = inv_refund and movement_type = 'store_sale';
  perform refund_invoice_recorded(inv_refund, jsonb_build_array(jsonb_build_object('invoice_item_id', it, 'amount', 200)),
    jsonb_build_array(jsonb_build_object('payment_id', pay, 'amount', 200)), mv, 'Returned', gen_random_uuid());
  if (select status from invoices where id = inv_refund) <> 'refunded' or (select status from invoices where id = inv_cancel) <> 'cancelled' then
    raise exception 'Fixture: expected a refunded and a cancelled invoice'; end if;
  -- (No FOC fixture: a completed_foc invoice is S$0, so it owed 0 before too.)

  page := invoice_list_page(p_store_id => pg_temp.t409_id('list_store'), p_limit => 200);
  for row in select * from jsonb_array_elements(page->'rows') loop
    if (row->>'id')::uuid in (inv_cancel, inv_refund) and (row->>'outstanding')::numeric <> 0 then
      raise exception 'FAIL 7: % (%) shows % outstanding', row->>'invoice_no', row->>'status', row->>'outstanding'; end if;
    if (row->>'id')::uuid = inv_unpaid and (row->>'outstanding')::numeric <> 100
       or (row->>'id')::uuid = inv_part and (row->>'outstanding')::numeric <> 180 then
      raise exception 'FAIL 7: an open invoice shows % outstanding', row->>'outstanding'; end if;
    -- The list and the invoice's own view agree.
    if (row->>'outstanding')::numeric <> (invoice_financial_position((row->>'id')::uuid)->>'outstanding')::numeric then
      raise exception 'FAIL 7: % shows % in the list and % on the invoice', row->>'invoice_no', row->>'outstanding',
        invoice_financial_position((row->>'id')::uuid)->>'outstanding'; end if;
  end loop;
  if (page->'summary'->>'matching')::int <> 4 or (page->'summary'->>'outstanding')::numeric <> 280
     or (page->'summary'->>'total_amount')::numeric <> 1100
     or (page->'summary'->>'closed_total')::numeric <> 700 or (page->'summary'->>'closed_count')::int <> 2 then
    raise exception 'FAIL 7: summary %', page->'summary'; end if;
  -- Sorted by Outstanding, the open invoices come first.
  select array_agg(x->>'id' order by n) into ord
    from jsonb_array_elements(invoice_list_page(p_store_id => pg_temp.t409_id('list_store'), p_sort_field => 'outstanding',
           p_sort_dir => 'desc', p_limit => 200)->'rows') with ordinality t(x, n);
  if ord[1]::uuid <> inv_part or ord[2]::uuid <> inv_unpaid then
    raise exception 'FAIL 7: sorted by Outstanding the first two are %, %', ord[1], ord[2]; end if;
  -- Filtered to cancelled: nothing outstanding, the total all closed.
  page := invoice_list_page(p_status => 'cancelled', p_store_id => pg_temp.t409_id('list_store'), p_limit => 200);
  if (page->'summary'->>'outstanding')::numeric <> 0 or (page->'summary'->>'closed_total')::numeric <> 500 then
    raise exception 'FAIL 7: the cancelled filter''s summary %', page->'summary'; end if;
  -- An open invoice with a line refunded: S$200 paid, one S$100 unit back.
  -- It still charges S$100 and holds S$100, so it owes nothing (the list
  -- showed the refund as owed: total 200 less paid 100).
  inv_part := pg_temp.t409_invoice('store', 2, false, 200);
  select id into it from invoice_items where invoice_id = inv_part;
  select id into pay from invoice_payments where invoice_id = inv_part;
  select jsonb_agg(jsonb_build_object('movement_id', id, 'sellable_quantity', 1)) into mv
    from stock_movements where invoice_id = inv_part and movement_type = 'store_sale';
  perform refund_invoice_recorded(inv_part, jsonb_build_array(jsonb_build_object('invoice_item_id', it, 'amount', 100)),
    jsonb_build_array(jsonb_build_object('payment_id', pay, 'amount', 100)), mv, 'One returned', gen_random_uuid());
  select x into row from jsonb_array_elements(invoice_list_page(p_store_id => pg_temp.t409_id('store'), p_limit => 200)->'rows') x
   where (x->>'id')::uuid = inv_part;
  if row->>'status' <> 'paid' or (row->>'paid_amount')::numeric <> 100 or (row->>'outstanding')::numeric <> 0
     or (invoice_financial_position(inv_part)->>'outstanding')::numeric <> 0 then
    raise exception 'FAIL 7: after a part refund the list shows % outstanding (status %, paid %), the invoice %',
      row->>'outstanding', row->>'status', row->>'paid_amount', invoice_financial_position(inv_part)->>'outstanding'; end if;
  -- Part-paid and part-refunded: S$300 (3 units), S$250 paid, one unit back:
  -- it charges S$200, holds S$150, owes S$50.
  inv_part := pg_temp.t409_invoice('store', 3, false, 250);
  select id into it from invoice_items where invoice_id = inv_part;
  select id into pay from invoice_payments where invoice_id = inv_part;
  select jsonb_agg(jsonb_build_object('movement_id', id, 'sellable_quantity', 1)) into mv
    from stock_movements where invoice_id = inv_part and movement_type = 'store_sale';
  if mv is null then
    -- A part-paid sale has taken no stock yet; nothing to return.
    mv := '[]'::jsonb; end if;
  perform refund_invoice_recorded(inv_part, jsonb_build_array(jsonb_build_object('invoice_item_id', it, 'amount', 100)),
    jsonb_build_array(jsonb_build_object('payment_id', pay, 'amount', 100)), mv, 'One cancelled', gen_random_uuid());
  select x into row from jsonb_array_elements(invoice_list_page(p_store_id => pg_temp.t409_id('store'), p_limit => 200)->'rows') x
   where (x->>'id')::uuid = inv_part;
  if (row->>'outstanding')::numeric <> 50
     or (row->>'outstanding')::numeric <> (invoice_financial_position(inv_part)->>'outstanding')::numeric then
    raise exception 'FAIL 7: a part-paid, part-refunded invoice shows % outstanding (status %, paid %), the invoice %',
      row->>'outstanding', row->>'status', row->>'paid_amount', invoice_financial_position(inv_part)->>'outstanding'; end if;
  -- A refund recorded before refunds named their lines (9 such invoices on
  -- production, 9 Oct 2026): refunded, but still "charging" its total. It
  -- owes nothing all the same.
  inv_refund := pg_temp.t409_invoice('store', 1, false, 0);
  update invoices set status = 'refunded' where id = inv_refund;
  select x into row from jsonb_array_elements(invoice_list_page(p_store_id => pg_temp.t409_id('store'), p_limit => 200)->'rows') x
   where (x->>'id')::uuid = inv_refund;
  if invoice_charge_total(inv_refund) <> 100 or (row->>'outstanding')::numeric <> 0
     or (invoice_financial_position(inv_refund)->>'outstanding')::numeric <> 0 then
    raise exception 'FAIL 7: a refunded invoice from before line refunds shows % outstanding', row->>'outstanding'; end if;
  raise notice 'PASS 7: the list shows 0 outstanding on cancelled and refunded invoices (one refunded before refunds named their lines included), agreeing with the invoice''s own view; open invoices unchanged; the summary''s outstanding leaves them out and says how much of the total is cancelled or refunded; sorting by Outstanding puts what is owed first; an open invoice with a line refunded owes what it still charges less what it holds (0 when paid, S$50 when S$250 of S$300 was paid and S$100 refunded)';
end $$;

rollback;
