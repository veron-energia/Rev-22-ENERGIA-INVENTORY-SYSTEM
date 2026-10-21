-- 417: invoice requests, deleting an invoice, and the amount owed back.
--
-- Audit findings INVOICES-AFTER-M2, -AFTER-14, -CREATE-14 and -409-Q1, with
-- the Owner's answers of 9 Oct 2026 (Q2: on cancelling a part-used sale the
-- Owner or Manager states how much is owed back; Q4: any staff member may
-- delete a draft or unpaid invoice, with a reason that is kept).
--   1. A request ID answers only the request it was used for: a replay on
--      another invoice, with another action or with other lines is refused,
--      not replayed.
--   2. Rejecting needs the approver's own reason; invoice_request_status
--      tells staff of the invoice's store that a request is waiting or was
--      rejected, and why, but not the requester's own reason; other stores
--      and logins that are not staff get 42501.
--   3. delete_invoice(uuid, text): draft and unpaid only, a reason required
--      and kept in the history (write_audit_ex, with the store); the
--      one-argument version is gone.
--   4. A cancellation whose customer had part of the sale: the amount stated
--      is the refund due, recorded up to it and no more, and the rest is kept
--      for what was used. Unstated, the reviewed refund is the default; more
--      than is held is refused; with the money paid back at once nothing more
--      is owed; a later cancellation states it again.
--   5. Therapy that has started, by its dates too (410), is not cancelled
--      around (363 rule C): a direct cancellation is refused, and the guided
--      one ends it on the Owner or Manager's override.
-- Per-line override amounts (S12) and the rest of 363's rules are in
-- promotion-therapy.sql; rewards in scripts/invoices/tests/reward-withdrawal.sql;
-- rentals in scripts/rentals/tests/receive-to-source.sql.
--
-- Needs 417 (run with it in the same transaction on a copy of production's
-- schema). Disposable database only; everything is rolled back. Every name,
-- phone, number and amount here is invented (@tests.invalid).
\set ON_ERROR_STOP on
begin;

create temp table t417(k text primary key, id uuid);
create function pg_temp.t417_id(p_k text) returns uuid language sql as $f$ select id from t417 where k = p_k $f$;
-- Acts as one of the fixture's logins, signed in (the role the browser has).
create function pg_temp.t417_as(p_k text) returns void language plpgsql as $f$
declare v uuid := coalesce(pg_temp.t417_id(p_k), gen_random_uuid());
begin
  perform set_config('request.jwt.claims', json_build_object('sub', v, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v::text, true);
end $f$;
-- Runs p_sql and expects a refusal whose message contains p_like (or, with
-- p_like '42501', that SQLSTATE).
create function pg_temp.t417_refused(p_label text, p_sql text, p_like text) returns void language plpgsql as $f$
begin
  begin
    execute p_sql;
  exception when others then
    if p_like = '42501' then
      if sqlstate <> '42501' then raise exception 'FAIL %: refused with % "%", not 42501', p_label, sqlstate, sqlerrm; end if;
    elsif sqlerrm not like '%' || p_like || '%' then
      raise exception 'FAIL %: refused, but with "%" (expected "%")', p_label, sqlerrm, p_like; end if;
    return;
  end;
  raise exception 'FAIL %: was not refused', p_label;
end $f$;

do $$
declare own uuid := gen_random_uuid(); mgr uuid := gen_random_uuid(); stf uuid := gen_random_uuid(); stf2 uuid := gen_random_uuid();
  stf3 uuid := gen_random_uuid(); sa uuid; sb uuid; c uuid; pm uuid; p uuid; ts uuid; tp uuid;
begin
  insert into auth.users(id, email) values (own, 't417-own@tests.invalid'), (mgr, 't417-mgr@tests.invalid'),
    (stf, 't417-stf@tests.invalid'), (stf2, 't417-stf2@tests.invalid'), (stf3, 't417-stf3@tests.invalid');
  insert into profiles(id, full_name, email, role, is_active) values
    (own, 'T417 Owner', 't417-own@tests.invalid', 'owner', true),
    (mgr, 'T417 Manager', 't417-mgr@tests.invalid', 'manager', true),
    (stf, 'T417 Staff', 't417-stf@tests.invalid', 'staff', true),
    (stf2, 'T417 Other Staff', 't417-stf2@tests.invalid', 'staff', true),
    (stf3, 'T417 Same Store Staff', 't417-stf3@tests.invalid', 'staff', true);
  perform set_config('request.jwt.claim.sub', own::text, true);
  insert into stores(name, code, country_code) values ('T417 Store A', 'T417A', 'SG') returning id into sa;
  insert into stores(name, code, country_code) values ('T417 Store B', 'T417B', 'SG') returning id into sb;
  insert into user_store_assignments(user_id, store_id) values (mgr, sa), (stf, sa), (stf2, sb), (stf3, sa);
  insert into customers(full_name, phone) values ('T417 Buyer', '+61491570157') returning id into c;
  insert into payment_methods(name, is_active) values ('T417 PayNow', true) returning id into pm;
  insert into products(name, sku, product_type) values ('T417 Item', 'T417I', 'own') returning id into p;
  insert into store_inventory(store_id, product_id, current_qty) values (sa, p, 100);
  perform set_product_prices(sa, p, 100, 100, 'available');
  insert into therapy_services(service_code, name, standard_price, duration_minutes, is_active)
    values ('T417S30', 'T417 Session', 30, 30, true) returning id into ts;
  insert into therapy_service_stores(service_id, store_id) values (ts, sa);
  insert into unlimited_therapy_packages(name, duration_months) values ('T417 Therapy 1m', 1) returning id into tp;
  insert into unlimited_therapy_store_prices(package_id, store_id, selling_price, available_at_store) values (tp, sa, 150, true);
  insert into t417 values ('own', own), ('mgr', mgr), ('stf', stf), ('stf2', stf2), ('stf3', stf3), ('store_a', sa), ('store_b', sb),
    ('customer', c), ('paynow', pm), ('product', p), ('session', ts), ('therapy', tp);
end $$;

-- One sale of `kind` (product, session, therapy), quantity q, paid `paid` (0: none).
create function pg_temp.t417_sale(p_kind text, p_qty int, p_paid numeric) returns uuid language plpgsql as $f$
declare v_inv uuid; v_line jsonb;
begin
  v_line := case p_kind
    when 'product' then jsonb_build_object('kind', 'product', 'product_id', pg_temp.t417_id('product'), 'quantity', p_qty)
    when 'session' then jsonb_build_object('kind', 'therapy', 'therapy_service_id', pg_temp.t417_id('session'), 'quantity', p_qty)
    when 'therapy' then jsonb_build_object('kind', 'therapy', 'therapy_package_id', pg_temp.t417_id('therapy'), 'quantity', p_qty) end;
  v_inv := create_invoice(pg_temp.t417_id('store_a'), pg_temp.t417_id('customer'), null, jsonb_build_array(v_line));
  if p_paid > 0 then
    perform pay_invoice(v_inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t417_id('paynow'), 'amount', p_paid)));
  end if;
  return v_inv;
end $f$;
-- The money still held recorded as paid back, as "Record refund paid" sends it.
create function pg_temp.t417_paid_back(p_inv uuid, p_amount numeric) returns text language plpgsql as $f$
begin
  perform refund_invoice_recorded(p_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', null, 'amount', p_amount)),
    jsonb_build_array(jsonb_build_object('payment_id',
      (select id from invoice_payments where invoice_id = p_inv and entry_kind = 'receipt' order by created_at limit 1), 'amount', p_amount)),
    '[]'::jsonb, 'Paid back', gen_random_uuid());
  return 'recorded';
exception when others then return sqlerrm;
end $f$;
-- A part-used sale: three S$30 sessions paid S$90, one delivered.
create function pg_temp.t417_used_sessions() returns uuid language plpgsql as $f$
declare v_inv uuid;
begin
  perform pg_temp.t417_as('own');
  v_inv := pg_temp.t417_sale('session', 3, 90);
  update customer_therapy_sessions set quantity_used = 1 where invoice_id = v_inv and is_current;
  return v_inv;
end $f$;

-- ===== 1. A request ID answers only its own request (AFTER-M2) =====
do $$
declare inv uuid; inv_b uuid; rid uuid := gen_random_uuid(); r jsonb;
  inv_c uuid; li uuid; rid2 uuid := gen_random_uuid(); r2 jsonb;
begin
  perform pg_temp.t417_as('own');
  inv := pg_temp.t417_sale('product', 2, 200);
  inv_b := pg_temp.t417_sale('product', 2, 200);
  perform pg_temp.t417_as('stf');
  r := request_invoice_action_v2(inv, 'refund_full', '[]', 'Customer returned both', null, rid);
  if r->>'status' <> 'pending' then raise exception 'FAIL 1: no request: %', r; end if;
  if not coalesce((request_invoice_action_v2(inv, 'refund_full', '[]', 'Customer returned both', null, rid)->>'replayed')::boolean, false) then
    raise exception 'FAIL 1: the same request again was not replayed'; end if;
  perform pg_temp.t417_refused('1 another action', format(
    'select request_invoice_action_v2(%L, ''cancel'', ''[]'', ''Changed my mind'', null, %L)', inv, rid),
    'This request ID was already used for a different request');
  perform pg_temp.t417_refused('1 other lines', format(
    'select request_invoice_action_v2(%L, ''refund_partial'', %L, ''One back'', null, %L)', inv,
    jsonb_build_array(jsonb_build_object('invoice_item_id', (select id from invoice_items where invoice_id = inv), 'quantity', 1)), rid),
    'This request ID was already used for a different request');
  -- The same action and lines on another invoice: refused, and nothing is
  -- raised there (the ID never answers with another invoice's request).
  perform pg_temp.t417_refused('1 another invoice', format(
    'select request_invoice_action_v2(%L, ''refund_full'', ''[]'', ''Customer returned both'', null, %L)', inv_b, rid),
    'This request ID was already used for a different request');
  if exists (select 1 from approval_requests where related_record_id = inv_b) then
    raise exception 'FAIL 1: a request was raised on the other invoice'; end if;
  perform pg_temp.t417_refused('1 a second request', format(
    'select request_invoice_action_v2(%L, ''cancel'', ''[]'', ''Another'', null, %L)', inv, gen_random_uuid()),
    'already waiting for approval');
  if (select count(*) from approval_requests where related_record_id = inv) <> 1
     or (select payload->>'action' from approval_requests where related_record_id = inv) <> 'refund_full' then
    raise exception 'FAIL 1: the request changed or a second was raised'; end if;
  -- The same action with other lines under the same ID: refused too (the
  -- action is the same, so only the lines tell them apart).
  perform pg_temp.t417_as('own');
  inv_c := pg_temp.t417_sale('product', 2, 200);
  li := (select id from invoice_items where invoice_id = inv_c);
  perform pg_temp.t417_as('stf');
  r2 := request_invoice_action_v2(inv_c, 'refund_partial',
    jsonb_build_array(jsonb_build_object('invoice_item_id', li, 'quantity', 1)), 'One back', null, rid2);
  if r2->>'status' <> 'pending' then raise exception 'FAIL 1: no part refund request: %', r2; end if;
  perform pg_temp.t417_refused('1 other lines, same action', format(
    'select request_invoice_action_v2(%L, ''refund_partial'', %L, ''One back'', null, %L)', inv_c,
    jsonb_build_array(jsonb_build_object('invoice_item_id', li, 'quantity', 2)), rid2),
    'This request ID was already used for a different request');
  if (select count(*) from approval_requests where related_record_id = inv_c) <> 1
     or (select payload->'lines'->0->>'quantity' from approval_requests where related_record_id = inv_c) is distinct from '1' then
    raise exception 'FAIL 1: the part refund request changed: %',
      (select payload->'lines' from approval_requests where related_record_id = inv_c); end if;
  insert into t417 values ('inv1', inv), ('req1', (r->>'request_id')::uuid);
  raise notice 'PASS 1: a request ID replays only the same request; another invoice, another action or other lines under it are refused, and nothing is raised twice';
end $$;

-- ===== 2. A rejection says why, and the invoice shows it (AFTER-14) =====
do $$
declare inv uuid := pg_temp.t417_id('inv1'); req uuid := pg_temp.t417_id('req1'); s jsonb;
begin
  perform pg_temp.t417_as('stf');
  s := invoice_request_status(inv);
  if not (s->>'pending')::boolean or (s->>'can_review')::boolean or s#>>'{request,request_id}' <> req::text
     or s#>>'{request,action}' <> 'refund_full' or s#>>'{request,requested_by}' <> 'T417 Staff'
     or (s#>>'{request,legacy}')::boolean then
    raise exception 'FAIL 2: staff do not see the waiting request: %', s; end if;
  -- The requester's own reason is not given out: another member of staff of
  -- the same store sees that a request waits, by whom and when, not why.
  if s->'request' ? 'reason' then raise exception 'FAIL 2: the requester''s reason is given out: %', s; end if;
  perform pg_temp.t417_as('stf3');
  s := invoice_request_status(inv);
  if not (s->>'pending')::boolean or s#>>'{request,request_id}' is distinct from req::text
     or s#>>'{request,requested_by}' is distinct from 'T417 Staff' or s->'request' ? 'reason'
     or s::text like '%Customer returned both%' then
    raise exception 'FAIL 2: other staff of the store do not see the request as they should: %', s; end if;
  perform pg_temp.t417_as('mgr');
  if not (invoice_request_status(inv)->>'can_review')::boolean then raise exception 'FAIL 2: a Manager cannot review it'; end if;
  perform pg_temp.t417_as('stf2');
  perform pg_temp.t417_refused('2 other store', format('select invoice_request_status(%L)', inv), '42501');
  perform pg_temp.t417_as('nobody');
  perform pg_temp.t417_refused('2 not staff', format('select invoice_request_status(%L)', inv), '42501');

  perform pg_temp.t417_as('mgr');
  perform pg_temp.t417_refused('2 no reason', format('select resolve_invoice_action_v2(%L, false, null)', req),
    'Give a reason for rejecting this request');
  perform pg_temp.t417_refused('2 blank reason', format('select resolve_invoice_action_v2(%L, false, ''   '')', req),
    'Give a reason for rejecting this request');
  if (select status from approval_requests where id = req) <> 'pending' then raise exception 'FAIL 2: a refused rejection changed the request'; end if;
  perform resolve_invoice_action_v2(req, false, 'Outside the refund terms');
  perform pg_temp.t417_as('stf');
  s := invoice_request_status(inv);
  if (s->>'pending')::boolean or s#>>'{request,status}' <> 'rejected' or s#>>'{request,rejection_reason}' <> 'Outside the refund terms'
     or s#>>'{request,resolved_by}' <> 'T417 Manager' or s#>>'{request,resolved_at}' is null then
    raise exception 'FAIL 2: the rejection does not show on the invoice: %', s; end if;
  -- An invoice with no request has none to show.
  perform pg_temp.t417_as('own');
  inv := pg_temp.t417_sale('product', 1, 0);
  if invoice_request_status(inv)->'request' <> 'null'::jsonb or (invoice_request_status(inv)->>'pending')::boolean then
    raise exception 'FAIL 2: an invoice with no request shows one'; end if;
  -- A waiting request shows before an older rejected one.
  perform pg_temp.t417_as('stf');
  perform request_invoice_action_v2(pg_temp.t417_id('inv1'), 'cancel', '[]', 'Try again as a cancellation', null, gen_random_uuid());
  if invoice_request_status(pg_temp.t417_id('inv1'))#>>'{request,action}' <> 'cancel'
     or not (invoice_request_status(pg_temp.t417_id('inv1'))->>'pending')::boolean then
    raise exception 'FAIL 2: the waiting request does not come first'; end if;
  raise notice 'PASS 2: rejecting needs the approver''s own reason; staff of the store see a waiting request (who, when, what, not the requester''s reason) and a rejection (by whom, why); Managers may review; another store''s staff and logins that are not staff are refused';
end $$;

-- ===== 3. Deleting an invoice (CREATE-14, the Owner's Q4) =====
do $$
declare inv uuid; foc uuid; req uuid; creq uuid; cnl uuid; paid uuid; part uuid; drf uuid; v text;
begin
  perform pg_temp.t417_as('own');
  inv := pg_temp.t417_sale('product', 1, 0);
  paid := pg_temp.t417_sale('product', 1, 100);
  part := pg_temp.t417_sale('product', 2, 50);
  insert into invoices (invoice_no, store_id, customer_id, created_by, status, subtotal, total_amount, business_date)
    values ('T417-FOC', pg_temp.t417_id('store_a'), pg_temp.t417_id('customer'), pg_temp.t417_id('own'), 'completed_foc', 0, 0, sg_today())
    returning id into foc;
  insert into invoices (invoice_no, store_id, customer_id, created_by, status, subtotal, total_amount, business_date)
    values ('T417-REQ', pg_temp.t417_id('store_a'), pg_temp.t417_id('customer'), pg_temp.t417_id('own'), 'refund_requested', 0, 0, sg_today())
    returning id into req;
  insert into invoices (invoice_no, store_id, customer_id, created_by, status, subtotal, total_amount, business_date)
    values ('T417-CREQ', pg_temp.t417_id('store_a'), pg_temp.t417_id('customer'), pg_temp.t417_id('own'), 'cancellation_requested', 0, 0, sg_today())
    returning id into creq;
  insert into invoices (invoice_no, store_id, customer_id, created_by, status, subtotal, total_amount, business_date)
    values ('T417-CNL', pg_temp.t417_id('store_a'), pg_temp.t417_id('customer'), pg_temp.t417_id('own'), 'cancelled', 0, 0, sg_today())
    returning id into cnl;
  insert into invoices (invoice_no, store_id, customer_id, created_by, status, subtotal, total_amount, business_date)
    values ('T417-DRAFT', pg_temp.t417_id('store_a'), pg_temp.t417_id('customer'), pg_temp.t417_id('own'), 'draft', 0, 0, sg_today())
    returning id into drf;

  if to_regprocedure('public.delete_invoice(uuid)') is not null
     or (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'delete_invoice') <> 1 then
    raise exception 'FAIL 3: the one-argument delete_invoice is still there'; end if;

  perform pg_temp.t417_as('stf');
  perform pg_temp.t417_refused('3 no reason', format('select delete_invoice(%L)', inv), 'Give a short reason for deleting this invoice');
  perform pg_temp.t417_refused('3 blank reason', format('select delete_invoice(%L, '' '')', inv), 'Give a short reason for deleting this invoice');
  foreach v in array array['a completed FOC invoice', 'waiting for a refund decision',
                           'waiting for a cancellation decision', 'cancelled', 'paid', 'part paid'] loop
    perform pg_temp.t417_refused('3 ' || v, format('select delete_invoice(%L, ''Mistake'')',
      case v when 'a completed FOC invoice' then foc when 'waiting for a refund decision' then req
             when 'waiting for a cancellation decision' then creq when 'cancelled' then cnl
             when 'paid' then paid else part end),
      'is ' || v || ', so it cannot be deleted. Only a draft or unpaid invoice can be deleted');
  end loop;
  perform pg_temp.t417_as('stf2');
  perform pg_temp.t417_refused('3 other store', format('select delete_invoice(%L, ''Mistake'')', inv), '42501');
  perform pg_temp.t417_as('nobody');
  perform pg_temp.t417_refused('3 not staff', format('select delete_invoice(%L, ''Mistake'')', inv), '42501');
  if exists (select 1 from invoices where id in (inv, foc, req, creq, cnl, paid, part, drf) and deleted_at is not null) then
    raise exception 'FAIL 3: a refused delete deleted something'; end if;

  perform pg_temp.t417_as('stf');
  perform delete_invoice(inv, '  Made by mistake ');
  if (select deleted_at from invoices where id = inv) is null then raise exception 'FAIL 3: the unpaid invoice was not deleted'; end if;
  if not exists (select 1 from audit_logs where record_id = inv and action = 'invoice_deleted' and reason = 'Made by mistake'
                  and new_data->>'reason' = 'Made by mistake' and store_id = pg_temp.t417_id('store_a')
                  and changed_by = pg_temp.t417_id('stf')) then
    raise exception 'FAIL 3: the reason, the store and who deleted it were not kept'; end if;
  perform delete_invoice(inv, 'Again');
  if (select count(*) from audit_logs where record_id = inv and action = 'invoice_deleted') <> 1 then
    raise exception 'FAIL 3: deleting again wrote again'; end if;
  perform delete_invoice(drf, 'Draft not needed');
  if (select deleted_at from invoices where id = drf) is null then raise exception 'FAIL 3: a draft was not deleted'; end if;
  raise notice 'PASS 3: any staff member of the store deletes a draft or unpaid invoice with a reason kept in the history; completed FOC, request statuses, cancelled, paid and part-paid invoices are refused, each named in words, and say to use Refund / Cancel; another store and logins that are not staff are refused; a second delete changes nothing; the one-argument version is gone';
end $$;

-- ===== 4. The amount owed back on a part-used cancellation (409-Q1, the Owner's Q2) =====
do $$
declare inv uuid; plan jsonb; res jsonb; req uuid; pos jsonb; msg text;
begin
  -- (A) One session of three delivered; the Manager states S$50 is owed back.
  inv := pg_temp.t417_used_sessions();
  perform pg_temp.t417_as('mgr');
  plan := invoice_action_plan(inv, 'cancel', '[]');
  if not coalesce((plan#>>'{refund_owed,needed}')::boolean, false) or (plan#>>'{refund_owed,held}')::numeric <> 90
     or plan#>'{refund_owed,used}' <> '["session_used"]'::jsonb or (plan->>'refund_due')::numeric <> 60 then
    raise exception 'FAIL 4A: the plan does not ask for the amount owed back: %', plan->'refund_owed'; end if;
  if invoice_action_plan(inv, 'refund_full', '[]')->'refund_owed' <> 'null'::jsonb then
    raise exception 'FAIL 4A: a refund asks for an amount owed back'; end if;
  req := (request_invoice_action_v2(inv, 'cancel', '[]', 'Customer moving away', null, gen_random_uuid())->>'request_id')::uuid;
  res := resolve_invoice_action_v2(req, true, 'Cancel; money later', plan->>'plan_hash',
    jsonb_build_array(jsonb_build_object('code', 'session_used', 'reason', 'One session delivered'),
                      jsonb_build_object('code', 'refund_owed', 'amount', 50, 'reason', 'Agreed with the customer')), null, false);
  if res->>'status' <> 'approved' or (res->>'refund_still_due')::numeric <> 50 or (res->>'refund_owed')::numeric <> 50 then
    raise exception 'FAIL 4A: %', res; end if;
  pos := invoice_financial_position(inv);
  if pos->>'status' <> 'cancelled' or (pos->>'refund_due')::numeric <> 50 or not (pos->>'refund_owed_stated')::boolean
     or (pos->>'kept_for_used')::numeric <> 40 or (pos->>'net_received')::numeric <> 90 then
    raise exception 'FAIL 4A: the invoice does not show S$50 owed and S$40 kept: %', pos; end if;
  if (select cancel_refund_owed from invoices where id = inv) <> 50
     or not exists (select 1 from audit_logs where record_id = inv and action = 'cancel_refund_owed_stated'
                     and (new_data->>'refund_owed')::numeric = 50) then
    raise exception 'FAIL 4A: the amount stated was not kept and audited'; end if;
  if (select (payload->>'refund_owed')::numeric from approval_requests where id = req) <> 50 then
    raise exception 'FAIL 4A: the approval does not record the amount stated'; end if;
  -- Recorded up to it, never more; the rest is kept.
  msg := pg_temp.t417_paid_back(inv, 60);
  if msg not like 'That is more than the S$50.00 still owed back on %' then raise exception 'FAIL 4A: S$60 of S$50 owed: %', msg; end if;
  if pg_temp.t417_paid_back(inv, 30) <> 'recorded' then raise exception 'FAIL 4A: S$30 of S$50 owed was refused'; end if;
  pos := invoice_financial_position(inv);
  if (pos->>'refund_due')::numeric <> 20 or (pos->>'kept_for_used')::numeric <> 40 or (pos->>'refunded')::numeric <> 30 then
    raise exception 'FAIL 4A: after S$30 recorded: %', pos; end if;
  if pg_temp.t417_paid_back(inv, 20) <> 'recorded' then raise exception 'FAIL 4A: the last S$20 was refused'; end if;
  pos := invoice_financial_position(inv);
  if (pos->>'refund_due')::numeric <> 0 or (pos->>'kept_for_used')::numeric <> 40 or (select cancel_refund_owed from invoices where id = inv) <> 0 then
    raise exception 'FAIL 4A: once paid back nothing is owed: %', pos; end if;
  if pg_temp.t417_paid_back(inv, 10) = 'recorded' then raise exception 'FAIL 4A: money kept for what was used was paid back'; end if;

  -- (B) Nothing stated: the reviewed refund is what is owed (S$60).
  inv := pg_temp.t417_used_sessions();
  perform pg_temp.t417_as('own');
  plan := invoice_action_plan(inv, 'cancel', '[]');
  req := (request_invoice_action_v2(inv, 'cancel', '[]', 'Moving', null, gen_random_uuid())->>'request_id')::uuid;
  res := resolve_invoice_action_v2(req, true, 'Cancel', plan->>'plan_hash',
    jsonb_build_array(jsonb_build_object('code', 'session_used', 'reason', 'One delivered')), null, false);
  if (invoice_financial_position(inv)->>'refund_due')::numeric <> 60 or (res->>'refund_still_due')::numeric <> 60 then
    raise exception 'FAIL 4B: unstated, the reviewed S$60 is not what is owed: %', invoice_financial_position(inv); end if;

  -- (C) More than the invoice holds, or less than 0: refused, nothing changed.
  inv := pg_temp.t417_used_sessions();
  plan := invoice_action_plan(inv, 'cancel', '[]');
  req := (request_invoice_action_v2(inv, 'cancel', '[]', 'Moving', null, gen_random_uuid())->>'request_id')::uuid;
  perform pg_temp.t417_refused('4C more than held', format('select resolve_invoice_action_v2(%L, true, ''x'', %L, %L, null, false)', req,
    plan->>'plan_hash', jsonb_build_array(jsonb_build_object('code', 'session_used', 'reason', 'One delivered'),
                                          jsonb_build_object('code', 'refund_owed', 'amount', 95, 'reason', 'x'))),
    'The amount owed back (S$95.00) is more than the S$90.00 this invoice holds');
  perform pg_temp.t417_refused('4C below 0', format('select resolve_invoice_action_v2(%L, true, ''x'', %L, %L, null, false)', req,
    plan->>'plan_hash', jsonb_build_array(jsonb_build_object('code', 'session_used', 'reason', 'One delivered'),
                                          jsonb_build_object('code', 'refund_owed', 'amount', -1, 'reason', 'x'))),
    'cannot be less than S$0');
  if (select status::text from invoices where id = inv) <> 'paid' or (select status from approval_requests where id = req) <> 'pending'
     or (select cancel_refund_owed from invoices where id = inv) is not null then
    raise exception 'FAIL 4C: a refused approval changed something'; end if;

  -- (D) The money paid back at once: the reviewed S$60 recorded, nothing more owed.
  res := resolve_invoice_action_v2(req, true, 'Cancel and pay back now', plan->>'plan_hash',
    jsonb_build_array(jsonb_build_object('code', 'session_used', 'reason', 'One delivered')), null, true);
  pos := invoice_financial_position(inv);
  if not (res->>'refund_recorded')::boolean or (res->>'refunded_amount')::numeric <> 60 or (pos->>'refund_due')::numeric <> 0
     or (pos->>'kept_for_used')::numeric <> 30 or (select cancel_refund_owed from invoices where id = inv) <> 0 then
    raise exception 'FAIL 4D: paid back at once: %, %', res, pos; end if;

  -- (E) Nothing used: all the money held is owed back, as before.
  inv := pg_temp.t417_sale('product', 1, 100);
  plan := invoice_action_plan(inv, 'cancel', '[]');
  if plan->'refund_owed' <> 'null'::jsonb then raise exception 'FAIL 4E: nothing used, yet an amount owed is asked'; end if;
  req := (request_invoice_action_v2(inv, 'cancel', '[]', 'Not wanted', null, gen_random_uuid())->>'request_id')::uuid;
  res := resolve_invoice_action_v2(req, true, 'Cancel', plan->>'plan_hash', '[]',
    (select jsonb_agg(jsonb_build_object('movement_id', s->>'movement_id', 'sellable_quantity', (s->>'proposed_sellable')::int,
       'damaged_quantity', 0, 'not_returned_quantity', 0)) from jsonb_array_elements(plan->'stock') s), false);
  pos := invoice_financial_position(inv);
  if (pos->>'refund_due')::numeric <> 100 or (pos->>'refund_owed_stated')::boolean or res->'refund_owed' <> 'null'::jsonb
     or (select cancel_refund_owed from invoices where id = inv) is not null then
    raise exception 'FAIL 4E: %', pos; end if;
  if pg_temp.t417_paid_back(inv, 100) <> 'recorded' then raise exception 'FAIL 4E: the S$100 was refused'; end if;

  -- (F) A cancellation made again (after a reopening) states it again: the
  -- earlier amount does not carry over, and with none stated, the old rule.
  inv := pg_temp.t417_used_sessions();
  perform pg_temp.t417_as('own');
  plan := invoice_action_plan(inv, 'cancel', '[]');
  req := (request_invoice_action_v2(inv, 'cancel', '[]', 'Moving', null, gen_random_uuid())->>'request_id')::uuid;
  perform resolve_invoice_action_v2(req, true, 'Cancel', plan->>'plan_hash',
    jsonb_build_array(jsonb_build_object('code', 'session_used', 'reason', 'One delivered'),
                      jsonb_build_object('code', 'refund_owed', 'amount', 45, 'reason', 'Agreed')), null, false);
  update invoices set status = 'paid' where id = inv;   -- as if reopened and settled again
  perform cancel_invoice_recorded(inv, 'Cancelled directly', gen_random_uuid());
  if (select cancel_refund_owed from invoices where id = inv) is not null then
    raise exception 'FAIL 4F: an earlier amount owed carried over'; end if;
  msg := pg_temp.t417_paid_back(inv, 45);
  if msg not like 'Part of what % sold has been used (sessions delivered), and no amount owed back was stated when it was cancelled%' then
    raise exception 'FAIL 4F: with no amount stated it was not refused: %', msg; end if;
  raise notice 'PASS 4: on a part-used cancellation the amount stated is the refund due, recorded up to it and never beyond, the rest kept for what was used and audited; unstated, the reviewed refund; more than held or below 0 refused with nothing changed; paid back at once, nothing more owed; nothing used, all of it as before; a later cancellation states it again';
end $$;

-- ===== 5. Started therapy is not cancelled around (363 rule C, with 410's dates) =====
do $$
declare inv uuid; u uuid; plan jsonb; req uuid; res jsonb;
begin
  perform pg_temp.t417_as('own');
  inv := pg_temp.t417_sale('therapy', 1, 150);
  select id into u from purchased_therapy_entitlements where invoice_id = inv;
  -- Its start date has come; the nightly refresh has not run yet.
  update purchased_therapy_entitlements set status = 'scheduled', activation_date = sg_today() - 1 where id = u;
  if not therapy_unit_consumed(u) then raise exception 'Fixture 5: the unit should read as started'; end if;
  perform pg_temp.t417_refused('5 direct cancel', format('select cancel_invoice_recorded(%L, ''Direct'', %L)', inv, gen_random_uuid()),
    'Therapy from this invoice has been started or has ended');
  if (select status from purchased_therapy_entitlements where id = u) <> 'scheduled' or (select status::text from invoices where id = inv) <> 'paid' then
    raise exception 'FAIL 5: a refused cancellation changed something'; end if;
  plan := invoice_action_plan(inv, 'cancel', '[]');
  if not exists (select 1 from jsonb_array_elements(plan->'overrides_required') o where o->>'code' = 'therapy_activated') then
    raise exception 'FAIL 5: the guided cancellation does not ask for the override'; end if;
  req := (request_invoice_action_v2(inv, 'cancel', '[]', 'Customer stopped', null, gen_random_uuid())->>'request_id')::uuid;
  res := resolve_invoice_action_v2(req, true, 'Ended on authorization', plan->>'plan_hash',
    jsonb_build_array(jsonb_build_object('code', 'therapy_activated', 'reason', 'One week used', 'amount', 100,
                                         'invoice_item_id', (select id from invoice_items where invoice_id = inv)),
                      jsonb_build_object('code', 'refund_owed', 'amount', 100, 'reason', 'Agreed')), null, false);
  if res->>'status' <> 'approved' or (select status from purchased_therapy_entitlements where id = u) <> 'refunded'
     or (select status::text from invoices where id = inv) <> 'cancelled'
     or not exists (select 1 from audit_logs where record_id = u and action = 'authorized_termination') then
    raise exception 'FAIL 5: the guided cancellation did not end the started therapy on the override: %', res; end if;
  if (invoice_financial_position(inv)->>'refund_due')::numeric <> 100 then
    raise exception 'FAIL 5: %', invoice_financial_position(inv); end if;
  raise notice 'PASS 5: therapy whose start date has come is not cancelled around directly (nothing changes); the guided cancellation ends it on the Owner or Manager''s override, audited, with the amount owed back stated';
end $$;

rollback;
