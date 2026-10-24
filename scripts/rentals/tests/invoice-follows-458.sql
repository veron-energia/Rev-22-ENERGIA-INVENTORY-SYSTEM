-- Rentals follow their invoice's Edit, Cancel and Refund (458).
--
-- The Owner, 22 Oct 2026, item 1 (the recommended answer to every question):
--   1. a full refund of the invoice or of the rental line, while the machine is out, ends the rental like
--      Cancel: no late fee, 'still with customer', received with Cancel's receive step;
--   2. a refund of some units: waiting, the rental is lowered to what is kept; out, it keeps running for
--      what is kept and the refunded units are received back;
--   3. an edit of a waiting rental's line (machine, quantity, rate, periods, start, Due back) moves the
--      rental with it, with the invoice's customer and store; the correction summary says so first;
--   4. while out: its rate, periods and Due back may change (and any other line); its machine or quantity
--      may not ('RNT-... is out with the customer: Return it first');
--   5. a move to another customer or store takes a waiting rental along and is refused while one is out;
--   6. reopening: a rental cancelled while out and not back runs again with its due date; one received
--      back gets a new waiting rental; a reopened FOC invoice raises its rentals;
--   7. 'Due back' blank is the start plus the periods by the rate type.
--
--   G  the md5s and the grants; what 458 relies on is unchanged.
--   C  Cancel unchanged: waiting cancelled; out cancelled awaiting return, no stock, received once; a
--      guided Cancel recording its refund in the same step ends the rental once (at the refund).
--   R  Refund: a full refund (direct and guided), the rental line in full beside a strap, another line
--      only, 1 of 2 machines out (split off and received), 1 of 2 waiting (lowered, or cancelled when
--      answered "not taking"), an amount short of a unit, a guided partial refund of 1 of 3 machines.
--   E  Edit: waiting follows (quantity, periods, fee, due date; the summary first and nothing kept); a
--      machine swap and dates; a customer and store move; out: extended, shortened, a due date before the
--      start refused, machine, quantity, removing the line, customer and store refused, another line and a
--      note allowed; a rental changed on the Special page is left by a correction of another line; a
--      rental out naming no line keeps the old refusal.
--   O  Reopen: running again (no stock, same due date, Return works); received back then a new waiting
--      rental; FOC raises one; refunded in full while out, reopened unpaid, then paid: running again.
--   F  After a refund or a reopening (the review of 24 Oct 2026): a waiting rental lowered by a refund
--      keeps the machines kept when its line is extended, refuses a line lowered to them and takes a
--      machine added; a line split between a rental out and one waiting keeps 2 machines when extended;
--      a refund on it takes the waiting machine first, or the one out when the waiting one is answered
--      "still taking"; a rental on an invoice that owes money (more machines, or a strap added) is
--      released only once it is paid in full (E3a/E3b, F8/F9).
--   D  'Due back' blank by rate type; the read-only list of rentals with the old due date.
--   M  458 twice changes nothing; its first run changes the six and adds the four; its self-test leaves
--      no row (when this file installs it).
--
-- Disposable local database only (a copy of production with 456 and 457 in); everything is rolled back.
-- Every name is invented ('T458 ...'), emails are @example.com and phones are ACMA's fictional range
-- (+61 2 5550 ....). It installs 458 twice (run with -v skip_install=1 where 458 is already installed).
-- Every check runs, then the file fails if any did.
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
create function pg_temp.fn_md5s() returns table(fn text, md5 text) language plpgsql as
$$begin
  perform set_config('search_path', 'public', true);
  return query select p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid))
                 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f';
end$$;
\if :{?skip_install}
\else
create temp table b458 as select * from pg_temp.fn_md5s();
create temp table r458 as select pg_temp.row_counts() as before;
\ir ../../../supabase/458_rentals_follow_invoice_changes.sql
create temp table m458 as select * from pg_temp.fn_md5s();
alter table r458 add column after1 jsonb;
update r458 set after1 = pg_temp.row_counts();
\ir ../../../supabase/458_rentals_follow_invoice_changes.sql
\endif
set local search_path = public;
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
create function pg_temp.putx(key text, val uuid) returns uuid language sql as
$$ insert into fx values (key, val) on conflict (k) do update set v = excluded.v returning v $$;
create function pg_temp.as_user(key text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.fx(key), 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', pg_temp.fx(key)::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
end $$;
-- The error a statement raises, or null.
create function pg_temp.msg(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return null;
exception when others then return sqlerrm;
end $$;

-- ═════ Fixtures ═════
do $$
declare o uuid := gen_random_uuid(); m uuid := gen_random_uuid(); s uuid := gen_random_uuid();
  sa uuid; sb uuid; wh uuid; ca uuid; cb uuid; pm uuid; p uuid; p2 uuid; ps uuid; sp uuid; sp2 uuid;
begin
  insert into app_settings default values on conflict do nothing;
  insert into auth.users(id, email) values (o, 't458-owner@example.com'), (m, 't458-manager@example.com'), (s, 't458-staff@example.com');
  insert into profiles(id, full_name, email, role, is_active) values
    (o, 'T458 Owner', 't458-owner@example.com', 'owner', true),
    (m, 'T458 Manager', 't458-manager@example.com', 'manager', true),
    (s, 'T458 Staff', 't458-staff@example.com', 'staff', true);
  perform pg_temp.putx('owner', o); perform pg_temp.putx('manager', m); perform pg_temp.putx('staff', s);
  perform pg_temp.as_user('owner');
  insert into stores(name, code, country_code) values ('T458 Store A', 'T458A', 'SG') returning id into sa;
  insert into stores(name, code, country_code) values ('T458 Store B', 'T458B', 'SG') returning id into sb;
  insert into warehouses(name, code) values ('T458 Warehouse', 'T458W') returning id into wh;
  insert into user_store_assignments(user_id, store_id) values (m, sa), (m, sb), (s, sa);
  insert into customers(full_name, phone) values ('T458 Customer A', '+61255504621') returning id into ca;
  insert into customers(full_name, phone) values ('T458 Customer B', '+61255504622') returning id into cb;
  insert into payment_methods(name, is_active) values ('T458 Cash', true) returning id into pm;
  insert into products(name, sku, product_type) values ('T458 Machine', 'T458-M', 'own') returning id into p;
  insert into products(name, sku, product_type) values ('T458 Chair', 'T458-C', 'own') returning id into p2;
  insert into products(name, sku, product_type) values ('T458 Strap', 'T458-S', 'own') returning id into ps;
  insert into warehouse_inventory(warehouse_id, product_id, current_qty) values (wh, p, 20), (wh, p2, 20);
  insert into store_inventory(store_id, product_id, current_qty) values (sb, p, 6), (sa, ps, 30);
  perform set_product_prices(sa, ps, 20, 20, 'available');
  -- S$30 a day, S$150 a week, S$500 a month, S$4,000 a year; late fee S$15 a day.
  sp := upsert_special_product_from_product(null, p, 3000, 30, 150, 500, 4000, 15);
  sp2 := upsert_special_product_from_product(null, p2, 2000, 40, 200, 600, 5000, 25);
  perform pg_temp.putx('store_a', sa); perform pg_temp.putx('store_b', sb); perform pg_temp.putx('wh', wh);
  perform pg_temp.putx('cust_a', ca); perform pg_temp.putx('cust_b', cb); perform pg_temp.putx('cash', pm);
  perform pg_temp.putx('machine', p); perform pg_temp.putx('chair', p2); perform pg_temp.putx('strap', ps);
  perform pg_temp.putx('sp', sp); perform pg_temp.putx('sp2', sp2);
end $$;

-- A paid invoice at Store A for Customer A of one rental line (and a strap,
-- when asked); its id.
create function pg_temp.sale(p_qty int, p_periods int, p_type text default 'day', p_strap boolean default false,
                             p_start date default null, p_due date default null, p_pay boolean default true) returns uuid
language plpgsql as $$
declare v_inv uuid; v_items jsonb;
begin
  perform pg_temp.as_user('owner');
  v_items := jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('kind', 'rental', 'special_product_id', pg_temp.fx('sp'),
    'quantity', p_qty, 'rental_rate_type', p_type, 'rental_periods', p_periods,
    'rental_start_date', p_start, 'rental_return_date', p_due)));
  if p_strap then
    v_items := v_items || jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('strap'), 'quantity', 1));
  end if;
  v_inv := create_invoice(pg_temp.fx('store_a'), pg_temp.fx('cust_a'), null, v_items);
  if p_pay then
    perform pay_invoice(v_inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'),
      'amount', invoice_charge_total(v_inv))));
  end if;
  return v_inv;
end $$;
create function pg_temp.rline(p_inv uuid) returns uuid language sql as
$$ select id from invoice_items where invoice_id = p_inv and line_kind::text = 'rental' order by id limit 1 $$;
create function pg_temp.sline(p_inv uuid) returns uuid language sql as
$$ select id from invoice_items where invoice_id = p_inv and line_kind::text = 'product' order by id limit 1 $$;
create function pg_temp.rent(p_inv uuid) returns uuid language sql as
$$ select id from rentals where invoice_id = p_inv order by rental_no limit 1 $$;
create function pg_temp.rrow(p_r uuid) returns rentals language sql as $$ select * from rentals where id = p_r $$;
-- The invoice's lines as the page sends them, the rental line patched.
create function pg_temp.items(p_inv uuid, p_patch jsonb default '{}'::jsonb) returns jsonb language sql as $$
  select jsonb_agg(case when it.line_kind::text = 'rental' then
      jsonb_build_object('invoice_item_id', it.id, 'kind', 'rental', 'special_product_id', it.special_product_id,
        'quantity', it.quantity, 'rental_rate_type', it.rental_rate_type, 'rental_periods', it.rental_periods,
        'rental_start_date', it.rental_start_date, 'rental_return_date', it.rental_return_date) || p_patch
    else jsonb_build_object('invoice_item_id', it.id, 'kind', it.line_kind::text, 'product_id', it.product_id,
        'quantity', it.quantity) end order by it.id)
  from invoice_items it where it.invoice_id = p_inv $$;
create function pg_temp.correct(p_inv uuid, p_items jsonb, p_header jsonb default '{}'::jsonb, p_reason text default 'T458 correction')
returns jsonb language sql as $$ select correct_invoice(p_inv, p_items, p_header, p_reason, gen_random_uuid()) $$;
-- Released from the warehouse or from Store B.
create function pg_temp.release(p_r uuid, p_where text default 'warehouse') returns void language plpgsql as $$
begin
  perform pg_temp.as_user('owner');
  perform fulfil_special_doc('rental', p_r, case when p_where = 'store' then pg_temp.fx('store_b') else pg_temp.fx('wh') end, p_where);
end $$;
-- A refund recorded directly: these lines, taken from the payments in order.
create function pg_temp.refund(p_inv uuid, p_lines jsonb, p_reason text default 'T458 refund') returns jsonb language plpgsql as $$
declare v_total numeric; v_left numeric; v_src jsonb := '[]'::jsonb; p record; v_take numeric;
begin
  select coalesce(sum((e->>'amount')::numeric), 0) into v_total from jsonb_array_elements(p_lines) e;
  v_left := v_total;
  for p in select ip.id from invoice_payments ip where ip.invoice_id = p_inv order by ip.created_at, ip.id loop
    exit when v_left <= 0;
    v_take := least(v_left, invoice_payment_remaining(p.id));
    if v_take > 0 then v_src := v_src || jsonb_build_array(jsonb_build_object('payment_id', p.id, 'amount', v_take)); end if;
    v_left := v_left - v_take;
  end loop;
  return refund_invoice_recorded(p_inv, p_lines, v_src, '[]'::jsonb, p_reason, gen_random_uuid());
end $$;
create function pg_temp.wh_qty() returns int language sql as
$$ select coalesce((select current_qty from warehouse_inventory where warehouse_id = pg_temp.fx('wh') and product_id = pg_temp.fx('machine')), 0) $$;
create function pg_temp.store_qty() returns int language sql as
$$ select coalesce((select current_qty from store_inventory where store_id = pg_temp.fx('store_b') and product_id = pg_temp.fx('machine')), 0) $$;
create function pg_temp.audits(p_r uuid, p_action text) returns int language sql as
$$ select count(*)::int from audit_logs where record_id = p_r and action = p_action $$;
-- "Rentals out" as the Dashboard counts them.
create function pg_temp.dash_out(p_inv uuid) returns int language sql as
$$ select count(*)::int from rentals where invoice_id = p_inv and status::text in ('paid', 'active') $$;

-- ═════ G The md5s and the grants ═════
-- correct_invoice: 458's AFTER, or 464's (which builds on it), read as 458's here.
-- (464's correct_invoice and 463's preview_invoice_correction, where they are
-- in, are read as 458's: they build on it.)
select pg_temp.check((select replace(replace(string_agg(fn || '=' || md5, ', ' order by fn),
                                     '=04d647e13e9424a9375942e5812e91a2', '=af9451fa15c2cf790edd70f799bae336'),
                                     '=f26752231c100461e11caddc03c98a33', '=3047239c7418179e84927f6f00e7f2eb') from pg_temp.fn_md5s()
                       where fn in ('correct_invoice(uuid,jsonb,jsonb,text,uuid)', 'preview_invoice_correction(uuid,jsonb)',
                                    'settle_waiting_special_docs_on_refund(uuid,jsonb,text)', 'create_special_docs_for_invoice(uuid)',
                                    'reopen_invoice(uuid,text,uuid)', 'fulfil_special_doc(text,uuid,uuid,text)',
                                    'invoice_rental_correction_check(uuid,jsonb,uuid,uuid)',
                                    'invoice_rentals_follow_lines(uuid,jsonb,text)', 'rental_end_on_refund(uuid,integer,text)',
                                    'rentals_follow_refund(uuid,jsonb,text)'))
  = 'correct_invoice(uuid,jsonb,jsonb,text,uuid)=af9451fa15c2cf790edd70f799bae336, '
 || 'create_special_docs_for_invoice(uuid)=429f4ac315cb5d0557c2005807bad115, '
 || 'fulfil_special_doc(text,uuid,uuid,text)=9c3072e11013e8943b28d8a46854edc4, '
 || 'invoice_rental_correction_check(uuid,jsonb,uuid,uuid)=a7dca029412e83a9fb06d7499d68fa1f, '
 || 'invoice_rentals_follow_lines(uuid,jsonb,text)=e195b8e16322325b7790392ed827cec2, '
 || 'preview_invoice_correction(uuid,jsonb)=3047239c7418179e84927f6f00e7f2eb, '
 || 'rental_end_on_refund(uuid,integer,text)=e8770411643bb293b8029539b1ff4fcb, '
 || 'rentals_follow_refund(uuid,jsonb,text)=0426b050207ccb4fe0a991b3cafc9769, '
 || 'reopen_invoice(uuid,text,uuid)=0ff61e4ead121c198ea7f90a7fc78274, '
 || 'settle_waiting_special_docs_on_refund(uuid,jsonb,text)=edfd1f1beb7ab3b6739096a618cd6a96',
  'G1 the six patched and four new functions have 458''s AFTER md5s (correct_invoice: or 464''s; preview_invoice_correction: or 463''s)');
select pg_temp.check(not exists (
    select 1 from unnest(array['invoice_rental_correction_check(uuid,jsonb,uuid,uuid)', 'invoice_rentals_follow_lines(uuid,jsonb,text)',
                               'rental_end_on_refund(uuid,integer,text)', 'rentals_follow_refund(uuid,jsonb,text)',
                               'settle_waiting_special_docs_on_refund(uuid,jsonb,text)', 'create_special_docs_for_invoice(uuid)']) f
     where has_function_privilege('anon', 'public.' || f, 'execute') or has_function_privilege('authenticated', 'public.' || f, 'execute')
        or not has_function_privilege('service_role', 'public.' || f, 'execute')),
  'G2 the four new functions and the two internals patched are the service role''s alone');
select pg_temp.check(not exists (
    select 1 from unnest(array['correct_invoice(uuid,jsonb,jsonb,text,uuid)', 'preview_invoice_correction(uuid,jsonb)',
                               'reopen_invoice(uuid,text,uuid)', 'fulfil_special_doc(text,uuid,uuid,text)']) f
     where has_function_privilege('anon', 'public.' || f, 'execute') or not has_function_privilege('authenticated', 'public.' || f, 'execute')),
  'G3 correct_invoice, preview_invoice_correction, reopen_invoice and fulfil_special_doc: signed-in staff, never anon');
select pg_temp.check((select string_agg(fn || '=' || md5, ', ' order by fn) from pg_temp.fn_md5s()
                       where fn in ('cancel_invoice_rentals(uuid,text)', 'receive_returned_rental(uuid,uuid,text,text,uuid)',
                                    'invoice_rentals_awaiting_return(uuid)', 'refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)',
                                    'invoice_action_plan(uuid,text,jsonb)', 'update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)',
                                    'special_doc_invoice_problem(uuid,uuid)', 'special_docs_awaiting_fulfilment()'))
  = 'cancel_invoice_rentals(uuid,text)=15aef6f8c9ef2022810f2181f512b150, '
 || 'invoice_action_plan(uuid,text,jsonb)=383d618edb28c3c9a360242d038a022c, '
 || 'invoice_rentals_awaiting_return(uuid)=07621bd5ba0b8be5cf69460ac4212017, '
 || 'receive_returned_rental(uuid,uuid,text,text,uuid)=362b0175b60e12c97e427b5180e01960, '
 || 'refund_invoice_recorded(uuid,jsonb,jsonb,jsonb,text,uuid)=804ecd829cfecf713783a09a05d93c7e, '
 || 'special_doc_invoice_problem(uuid,uuid)=be2b8ec5a4003a1dca34e17a82f89932, '
 || 'special_docs_awaiting_fulfilment()=aed7e3b24ff192cbe09935c5e7488881, '
 || 'update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)=1f034561a461bdb46a1e6274e0d04606',
  'G4 Cancel, the receive step, refund_invoice_recorded, invoice_action_plan, update_invoice_internal, 393''s release check and the waiting list are unchanged');

-- ═════ C Cancel unchanged ═════
do $$
declare inv uuid; r uuid; w0 int; x jsonb;
begin
  -- Waiting: cancelled with its invoice.
  inv := pg_temp.sale(1, 2); r := pg_temp.rent(inv);
  perform cancel_invoice_recorded(inv, 'T458 cancel before release', gen_random_uuid());
  perform pg_temp.check((pg_temp.rrow(r)).status::text = 'cancelled' and not rental_awaiting_return(r)
      and pg_temp.audits(r, 'rental_cancelled_with_invoice') = 1,
    'C1 Cancel: a waiting rental is cancelled with its invoice, audited, nothing to receive');
  -- Out: cancelled while out, awaiting return, no stock moved; received once.
  inv := pg_temp.sale(1, 2); r := pg_temp.rent(inv);
  perform pg_temp.release(r);
  w0 := pg_temp.wh_qty();
  perform cancel_invoice_recorded(inv, 'T458 cancel while out', gen_random_uuid());
  perform pg_temp.check((pg_temp.rrow(r)).status::text = 'cancelled' and rental_awaiting_return(r)
      and (pg_temp.rrow(r)).notes like '%Cancelled with its invoice while still out; awaiting physical return: T458 cancel while out%'
      and pg_temp.audits(r, 'rental_cancelled_awaiting_return') = 1 and pg_temp.audits(r, 'rental_refunded_awaiting_return') = 0
      and pg_temp.wh_qty() = w0 and jsonb_array_length(invoice_rentals_awaiting_return(inv)) = 1 and pg_temp.dash_out(inv) = 0,
    'C2 Cancel: a rental out is cancelled, still with the customer, its words and audit as before, no stock moved, listed to receive');
  x := receive_returned_rental(r, null, 'good', 'T458 back', gen_random_uuid());
  perform pg_temp.check(pg_temp.wh_qty() = w0 + 1 and (x->>'returned_quantity')::int = 1
      and (receive_returned_rental(r, null, 'good', 'Again', null)->>'already_returned')::boolean and pg_temp.wh_qty() = w0 + 1,
    'C3 Cancel: received back into its warehouse once');
  -- A guided Cancel that records its refund in the same step: the refund ends
  -- the rental first (its words), the same state as Cancel's.
  inv := pg_temp.sale(1, 2); r := pg_temp.rent(inv);
  perform pg_temp.release(r);
  w0 := pg_temp.wh_qty();
  perform pg_temp.as_user('staff');
  x := request_invoice_action_v2(inv, 'cancel', '[]'::jsonb, 'T458 guided cancel', null, gen_random_uuid());
  perform pg_temp.as_user('owner');
  x := resolve_invoice_action_v2((x->>'request_id')::uuid, true, 'T458 approved', null, '[]'::jsonb, null, true);
  perform pg_temp.check(x->>'status' = 'approved' and (select status::text from invoices where id = inv) = 'cancelled'
      and (pg_temp.rrow(r)).status::text = 'cancelled' and rental_awaiting_return(r) and pg_temp.wh_qty() = w0
      and pg_temp.audits(r, 'rental_refunded_awaiting_return') + pg_temp.audits(r, 'rental_cancelled_awaiting_return') = 1
      and jsonb_array_length(invoice_rentals_awaiting_return(inv)) = 1,
    'C4 a guided Cancel recording its refund in the same step ends the rental once, still with the customer, no stock moved ('
      || case when pg_temp.audits(r, 'rental_refunded_awaiting_return') = 1 then 'ended at the refund' else 'ended at the cancellation' end || ')');
end $$;

-- ═════ R Refund ═════
do $$
declare inv uuid; r uuid; w0 int; x jsonb; aw jsonb; s0 int; ln uuid; m text;
begin
  -- R1 A full refund of the invoice with the rental out.
  inv := pg_temp.sale(1, 2); r := pg_temp.rent(inv); ln := pg_temp.rline(inv);
  perform pg_temp.release(r);
  w0 := pg_temp.wh_qty();
  perform pg_temp.refund(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', ln, 'amount', 60)), 'T458 refund in full');
  aw := invoice_rentals_awaiting_return(inv);
  perform pg_temp.check((select status::text from invoices where id = inv) = 'refunded'
      and (pg_temp.rrow(r)).status::text = 'cancelled' and rental_awaiting_return(r)
      and (pg_temp.rrow(r)).notes like '%Refunded while still out; awaiting physical return: T458 refund in full%'
      and pg_temp.audits(r, 'rental_refunded_awaiting_return') = 1 and pg_temp.wh_qty() = w0
      and jsonb_array_length(aw) = 1 and aw->0->>'invoice_item_id' = ln::text and pg_temp.dash_out(inv) = 0,
    'R1 a full refund ends the rental out like Cancel: cancelled, still with the customer, its words and audit row, no stock, listed on its line, off the Dashboard: ' || coalesce(aw::text, ''));
  m := pg_temp.msg(format('select return_rental_with_fee(%L, ''good'', true)', r));
  perform pg_temp.check(m like 'Only a rental that is out with the customer can be returned%',
    'R2 Return (with its late fee) refuses the refunded rental: ' || coalesce(m, 'returned'));
  x := receive_returned_rental(r, null, 'good', 'T458 back after the refund', gen_random_uuid());
  perform pg_temp.check(pg_temp.wh_qty() = w0 + 1 and (pg_temp.rrow(r)).stock_returned
      and jsonb_array_length(invoice_rentals_awaiting_return(inv)) = 0,
    'R3 it is received back into its warehouse with Cancel''s receive step');

  -- R4 The guided "Refund in full" (a request approved), rental out from a store.
  inv := pg_temp.sale(1, 2); r := pg_temp.rent(inv);
  perform pg_temp.release(r, 'store');
  s0 := pg_temp.store_qty();
  perform pg_temp.as_user('staff');
  x := request_invoice_action_v2(inv, 'refund_full', '[]'::jsonb, 'T458 guided refund', null, gen_random_uuid());
  perform pg_temp.as_user('owner');
  x := resolve_invoice_action_v2((x->>'request_id')::uuid, true, 'T458 approved');
  perform pg_temp.check(x->>'status' = 'approved' and (select status::text from invoices where id = inv) = 'refunded'
      and rental_awaiting_return(r) and pg_temp.store_qty() = s0
      and jsonb_array_length(invoice_rentals_awaiting_return(inv)) = 1,
    'R4 the guided Refund in full ends the rental out the same way (a store release; no stock moved): ' || coalesce(x->>'status', ''));

  -- R5 The rental line refunded in full beside a strap: only the rental ends.
  inv := pg_temp.sale(1, 2, 'day', true); r := pg_temp.rent(inv);
  perform pg_temp.release(r);
  perform pg_temp.refund(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.rline(inv), 'amount', 60)));
  perform pg_temp.check((select status::text from invoices where id = inv) = 'paid' and rental_awaiting_return(r)
      and jsonb_array_length(invoice_rentals_awaiting_return(inv)) = 1,
    'R5 the rental line refunded in full beside a strap ends the rental; the invoice stays paid for the strap');

  -- R6 A refund of the strap line only leaves the rental running.
  inv := pg_temp.sale(1, 2, 'day', true); r := pg_temp.rent(inv);
  perform pg_temp.release(r);
  perform refund_invoice_recorded(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.sline(inv), 'amount', 20)),
    jsonb_build_array(jsonb_build_object('payment_id', (select id from invoice_payments where invoice_id = inv limit 1), 'amount', 20)),
    jsonb_build_array(jsonb_build_object('movement_id', (select id from stock_movements where invoice_id = inv and movement_type::text = 'store_sale' limit 1),
      'sellable_quantity', 1, 'damaged_quantity', 0, 'not_returned_quantity', 0)), 'T458 strap back', gen_random_uuid());
  perform pg_temp.check((pg_temp.rrow(r)).status::text = 'active' and jsonb_array_length(invoice_rentals_awaiting_return(inv)) = 0,
    'R6 a refund of another line leaves the rental running, nothing to receive');
end $$;

do $$
declare inv uuid; r uuid; r2 uuid; w0 int; ln uuid; d uuid;
begin
  -- R7 1 of 2 machines out refunded: the rental keeps running for one, the other is split off to come back.
  inv := pg_temp.sale(2, 2); r := pg_temp.rent(inv); ln := pg_temp.rline(inv);
  perform pg_temp.release(r);
  w0 := pg_temp.wh_qty();
  perform pg_temp.refund(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', ln, 'amount', 60)), 'T458 one machine back');
  select id into r2 from rentals where invoice_id = inv and id <> r;
  perform pg_temp.check((pg_temp.rrow(r)).status::text = 'active' and (pg_temp.rrow(r)).quantity = 1
      and (pg_temp.rrow(r)).rental_fee = 60 and (pg_temp.rrow(r)).rate_amount = 30
      and r2 is not null and (pg_temp.rrow(r2)).quantity = 1 and (pg_temp.rrow(r2)).status::text = 'cancelled'
      and rental_awaiting_return(r2) and (pg_temp.rrow(r2)).invoice_item_id = ln
      and (pg_temp.rrow(r2)).warehouse_id = pg_temp.fx('wh') and (pg_temp.rrow(r2)).rental_fee = 60
      and (pg_temp.rrow(r2)).notes like 'Split from ' || (pg_temp.rrow(r)).rental_no || ': 1 of its 2 refunded.%'
      and pg_temp.audits(r, 'rental_part_refunded') = 1 and pg_temp.audits(r2, 'rental_refunded_awaiting_return') = 1
      and pg_temp.wh_qty() = w0 and (select status::text from invoices where id = inv) = 'paid',
    'R7 1 of 2 machines out refunded: the rental runs on for one (S$60), the refunded one is its own rental number, ended, from the same warehouse, to be received; no stock moved');
  perform pg_temp.check(jsonb_array_length(invoice_rentals_awaiting_return(inv)) = 1
      and invoice_rentals_awaiting_return(inv)->0->>'rental_id' = r2::text,
    'R8 the receive step lists the refunded machine on its line');
  perform receive_returned_rental(r2, null, 'good', 'T458 one back', gen_random_uuid());
  perform pg_temp.check(pg_temp.wh_qty() = w0 + 1 and (pg_temp.rrow(r)).status::text = 'active',
    'R9 the refunded machine goes back into the warehouse; the other keeps running');
  -- The other machine refunded too: the invoice is refunded and the rental ends.
  perform pg_temp.refund(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', ln, 'amount', 60)), 'T458 the other back');
  perform pg_temp.check((select status::text from invoices where id = inv) = 'refunded' and rental_awaiting_return(r)
      and (select count(*) from rentals where invoice_id = inv) = 2,
    'R10 the second machine refunded: the invoice is refunded and the rest of the rental ends, still with the customer');

  -- R11 1 of 2 machines waiting refunded, "still taking": lowered to one.
  inv := pg_temp.sale(2, 2); r := pg_temp.rent(inv); ln := pg_temp.rline(inv);
  perform pg_temp.refund(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', ln, 'amount', 60,
    'waiting', jsonb_build_array(jsonb_build_object('doc_id', r, 'still_taking', true)))));
  perform pg_temp.check((pg_temp.rrow(r)).status::text = 'awaiting_fulfilment' and (pg_temp.rrow(r)).quantity = 1
      and (pg_temp.rrow(r)).rental_fee = 60 and (pg_temp.rrow(r)).rate_amount = 30
      and pg_temp.audits(r, 'rental_part_refunded_waiting') = 1 and (select count(*) from rentals where invoice_id = inv) = 1,
    'R11 1 of 2 machines waiting refunded, still taking: the rental waits for one machine at S$60');
  -- With no answer: the same.
  inv := pg_temp.sale(2, 2); r := pg_temp.rent(inv);
  perform pg_temp.refund(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.rline(inv), 'amount', 60)));
  perform pg_temp.check((pg_temp.rrow(r)).status::text = 'awaiting_fulfilment' and (pg_temp.rrow(r)).quantity = 1,
    'R12 with no answer the waiting rental is lowered the same way');
  -- Answered "not taking": cancelled, as 393 does.
  inv := pg_temp.sale(2, 2); r := pg_temp.rent(inv);
  perform pg_temp.refund(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.rline(inv), 'amount', 60,
    'waiting', jsonb_build_array(jsonb_build_object('doc_id', r, 'still_taking', false)))));
  perform pg_temp.check((pg_temp.rrow(r)).status::text = 'cancelled' and (pg_temp.rrow(r)).quantity = 2
      and (pg_temp.rrow(r)).notes like '%Cancelled (refunded)%',
    'R13 answered "not taking", the waiting rental is cancelled (393, unchanged)');

  -- R14 An amount short of one machine's value changes nothing.
  inv := pg_temp.sale(2, 2); r := pg_temp.rent(inv);
  perform pg_temp.release(r);
  perform pg_temp.refund(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.rline(inv), 'amount', 59.98)));
  perform pg_temp.check((pg_temp.rrow(r)).status::text = 'active' and (pg_temp.rrow(r)).quantity = 2
      and (select count(*) from rentals where invoice_id = inv) = 1,
    'R14 a goodwill amount short of one machine (S$59.98 of S$60) ends nothing');

  -- R15 The guided partial refund of 1 of 3 machines out (a request approved).
  inv := pg_temp.sale(3, 2); r := pg_temp.rent(inv); ln := pg_temp.rline(inv);
  perform pg_temp.release(r);
  perform pg_temp.as_user('staff');
  d := (request_invoice_action_v2(inv, 'refund_partial', jsonb_build_array(jsonb_build_object('invoice_item_id', ln, 'quantity', 1)),
          'T458 one machine back', null, gen_random_uuid())->>'request_id')::uuid;
  perform pg_temp.as_user('owner');
  perform resolve_invoice_action_v2(d, true, 'T458 approved');
  perform pg_temp.check((pg_temp.rrow(r)).status::text = 'active' and (pg_temp.rrow(r)).quantity = 2 and (pg_temp.rrow(r)).rental_fee = 120
      and (select count(*) from rentals where invoice_id = inv and status::text = 'cancelled' and quantity = 1) = 1
      and jsonb_array_length(invoice_rentals_awaiting_return(inv)) = 1,
    'R15 the guided partial refund of 1 of 3 machines out: two keep running (S$120), the third is to be received');
end $$;

-- ═════ E Edit ═════
do $$
declare inv uuid; r uuid; ln uuid; pv jsonb; x jsonb; e jsonb; st date; m text; u jsonb; w0 int;
begin
  -- E1 Waiting: 1 x 2 days -> 2 x 3 days. The summary says so first and keeps nothing.
  inv := pg_temp.sale(1, 2); r := pg_temp.rent(inv); ln := pg_temp.rline(inv);
  st := (pg_temp.rrow(r)).start_date;
  pv := preview_invoice_correction(inv, jsonb_build_object('items', pg_temp.items(inv, '{"quantity": 2, "rental_periods": 3}'),
    'reason', 'T458 two machines'));
  e := (select q from jsonb_array_elements(pv->'effects') q where q->>'area' = 'rentals');
  perform pg_temp.check(e is not null and jsonb_array_length(e->'items') = 1
      and e->'items'->0->>'what' = (pg_temp.rrow(r)).rental_no || ' (waiting for a warehouse): 2 × 3 days, S$180.00, due back '
                                   || to_char(st + 3, 'DD/MM/YYYY') || ' (was ' || to_char(st + 2, 'DD/MM/YYYY') || ')'
                                   || '; released once the invoice is paid in full'
      and (pg_temp.rrow(r)).quantity = 1 and (pg_temp.rrow(r)).periods = 2 and pg_temp.audits(r, 'rental_follows_invoice_line') = 0,
    'E1 the correction summary lists the rental and what it becomes, before saving, and changes nothing: ' || coalesce(e::text, pv::text));
  x := pg_temp.correct(inv, pg_temp.items(inv, '{"quantity": 2, "rental_periods": 3}'), '{}'::jsonb, 'T458 two machines');
  perform pg_temp.check((pg_temp.rrow(r)).quantity = 2 and (pg_temp.rrow(r)).periods = 3 and (pg_temp.rrow(r)).rental_fee = 180
      and (pg_temp.rrow(r)).rate_amount = 60 and (pg_temp.rrow(r)).expected_return_date = st + 3
      and (pg_temp.rrow(r)).status::text = 'awaiting_fulfilment' and pg_temp.audits(r, 'rental_follows_invoice_line') = 1
      and jsonb_array_length(x->'rentals') = 1 and x->'rentals'->0->>'state' = 'waiting'
      and (select status::text from invoices where id = inv) = 'partially_paid',
    'E2 saved: the waiting rental follows (2 x 3 days, S$180, S$60 a day, due back start + 3), audited, in the answer; the invoice owes the difference');
  u := update_pending_rental(r, null, null, null, null, st + 4, null);
  perform pg_temp.check((u->>'difference')::numeric = 0 and (u->>'invoiced_fee')::numeric = 180,
    'E3 the Special page reads the fee as sold from the corrected line (a date change: difference S$0): ' || u::text);
  -- E3a/b Owing the S$120 difference, the rental waits for the payment; paid, it is released.
  w0 := pg_temp.wh_qty();
  m := pg_temp.msg(format('select pg_temp.release(%L)', r));
  perform pg_temp.check(m = (pg_temp.rrow(r)).rental_no || ' cannot be released yet: its invoice '
        || (select invoice_no from invoices where id = inv) || ' has S$120.00 owing. Take the payment first, then release it.'
      and (pg_temp.rrow(r)).status::text = 'awaiting_fulfilment' and pg_temp.wh_qty() = w0
      and exists (select 1 from special_docs_awaiting_fulfilment() s where s.doc_id = r),
    'E3a a waiting rental a correction raised to 2 machines on a part-paid invoice is not released before the S$120 is paid (still listed, no stock): ' || coalesce(m, 'released'));
  perform pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'), 'amount', 120)));
  perform pg_temp.release(r);
  perform pg_temp.check((select status::text from invoices where id = inv) = 'paid' and (pg_temp.rrow(r)).status::text = 'active'
      and pg_temp.wh_qty() = w0 - 2,
    'E3b paid in full, it is released: both machines go out');

  -- E4 Waiting: the machine swapped, the start and Due back given.
  inv := pg_temp.sale(1, 2); r := pg_temp.rent(inv);
  x := pg_temp.correct(inv, pg_temp.items(inv, jsonb_build_object('special_product_id', pg_temp.fx('sp2'),
    'rental_start_date', date '2027-03-01', 'rental_return_date', date '2027-03-05')), '{}'::jsonb, 'T458 the chair instead');
  perform pg_temp.check((pg_temp.rrow(r)).special_product_id = pg_temp.fx('sp2') and (pg_temp.rrow(r)).late_fee_per_day = 25
      and (pg_temp.rrow(r)).start_date = date '2027-03-01' and (pg_temp.rrow(r)).expected_return_date = date '2027-03-05'
      and (pg_temp.rrow(r)).rental_fee = 80 and x->'rentals'->0->>'what' like '%now T458 Chair%',
    'E4 a machine swapped on the line: the waiting rental is the new machine (its late fee), with the start and Due back given');

  -- E5 Waiting: the invoice moved to Customer B at Store B takes the rental along.
  inv := pg_temp.sale(1, 2); r := pg_temp.rent(inv);
  x := pg_temp.correct(inv, pg_temp.items(inv), jsonb_build_object('customer_id', pg_temp.fx('cust_b'), 'store_id', pg_temp.fx('store_b')),
    'T458 wrong customer and store');
  perform pg_temp.check((pg_temp.rrow(r)).customer_id = pg_temp.fx('cust_b') and (pg_temp.rrow(r)).store_id = pg_temp.fx('store_b')
      and (pg_temp.rrow(r)).periods = 2 and x->'rentals'->0->>'what' like '%moves to T458 Customer B; moves to T458 Store B',
    'E5 a correction moving the invoice to another customer and store moves its waiting rental with it: ' || coalesce(x->'rentals'->0->>'what', ''));

  -- E6 A waiting rental changed on the Special page keeps its terms when another line is corrected.
  inv := pg_temp.sale(1, 2, 'day', true); r := pg_temp.rent(inv);
  perform update_pending_rental(r, null, null, 4, null, null, null);
  x := pg_temp.correct(inv, (select jsonb_agg(case when q->>'kind' = 'product' then q || '{"quantity": 2}' else q end)
                               from jsonb_array_elements(pg_temp.items(inv)) q), '{}'::jsonb, 'T458 two straps');
  perform pg_temp.check((pg_temp.rrow(r)).periods = 4 and jsonb_array_length(x->'rentals') = 0,
    'E6 a correction of another line leaves a waiting rental changed on the Special page as it is');
end $$;

do $$
declare inv uuid; r uuid; ln uuid; x jsonb; st date; due0 date; m text; w0 int;
begin
  -- E7 Out: extended from 2 to 4 days; then shortened to 1.
  inv := pg_temp.sale(1, 2); r := pg_temp.rent(inv); ln := pg_temp.rline(inv);
  perform pg_temp.release(r);
  w0 := pg_temp.wh_qty();
  st := (pg_temp.rrow(r)).start_date; due0 := (pg_temp.rrow(r)).expected_return_date;
  x := pg_temp.correct(inv, pg_temp.items(inv, '{"rental_periods": 4}'), '{}'::jsonb, 'T458 two more days');
  perform pg_temp.check((pg_temp.rrow(r)).status::text = 'active' and (pg_temp.rrow(r)).periods = 4
      and (pg_temp.rrow(r)).expected_return_date = st + 4 and (pg_temp.rrow(r)).rental_fee = 120
      and x->'rentals'->0->>'state' = 'out' and pg_temp.wh_qty() = w0
      and (select (status::text, total_amount) = ('partially_paid'::text, 120::numeric) from invoices where id = inv),
    'E7 a rental out extended from 2 to 4 days: Due back moves to start + 4, S$120, still out, no stock; the invoice owes the S$60 difference');
  x := pg_temp.correct(inv, pg_temp.items(inv, '{"rental_periods": 1}'), '{}'::jsonb, 'T458 back early');
  perform pg_temp.check((pg_temp.rrow(r)).periods = 1 and (pg_temp.rrow(r)).expected_return_date = st + 1
      and (pg_temp.rrow(r)).rental_fee = 30 and (select status::text from invoices where id = inv) = 'paid',
    'E8 shortened to 1 day: Due back start + 1, S$30; the invoice is paid with S$30 to give back');
  m := pg_temp.msg(format('select pg_temp.correct(%L, %L::jsonb)', inv,
    pg_temp.items(inv, jsonb_build_object('rental_return_date', st - 1))));
  perform pg_temp.check(m = (pg_temp.rrow(r)).rental_no || ': "Due back" (' || to_char(st - 1, 'DD/MM/YYYY')
      || ') cannot be before the rental''s start (' || to_char(st, 'DD/MM/YYYY') || ').',
    'E9 a Due back before the start is refused in words: ' || coalesce(m, 'saved'));
  -- E10 Out: machine, quantity, removing the line, another customer, another store: refused.
  m := pg_temp.msg(format('select pg_temp.correct(%L, %L::jsonb)', inv, pg_temp.items(inv, '{"quantity": 2}')));
  perform pg_temp.check(m = (pg_temp.rrow(r)).rental_no || ' is out with the customer: Return it first. Its machine and quantity stay as they went out; its rate, periods and "Due back" can change.',
    'E10 a quantity change of a rental out is refused: ' || coalesce(m, 'saved'));
  m := pg_temp.msg(format('select pg_temp.correct(%L, %L::jsonb)', inv, pg_temp.items(inv, jsonb_build_object('special_product_id', pg_temp.fx('sp2')))));
  perform pg_temp.check(m like (pg_temp.rrow(r)).rental_no || ' is out with the customer: Return it first. Its machine and quantity%',
    'E11 a machine change of a rental out is refused: ' || coalesce(m, 'saved'));
  m := pg_temp.msg(format('select pg_temp.correct(%L, %L::jsonb)', inv,
    jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('strap'), 'quantity', 1))));
  perform pg_temp.check(m = (pg_temp.rrow(r)).rental_no || ' is out with the customer: Return it first. Its line cannot be removed while it is out.',
    'E12 removing the line of a rental out is refused: ' || coalesce(m, 'saved'));
  m := pg_temp.msg(format('select pg_temp.correct(%L, %L::jsonb, %L::jsonb)', inv, pg_temp.items(inv),
    jsonb_build_object('customer_id', pg_temp.fx('cust_b'))));
  perform pg_temp.check(m = (pg_temp.rrow(r)).rental_no || ' is out with the customer: Return it first. The invoice cannot move to another customer or store while its rental is out.',
    'E13 moving the invoice to another customer while its rental is out is refused: ' || coalesce(m, 'saved'));
  m := pg_temp.msg(format('select pg_temp.correct(%L, %L::jsonb, %L::jsonb)', inv, pg_temp.items(inv),
    jsonb_build_object('store_id', pg_temp.fx('store_b'))));
  perform pg_temp.check(m like (pg_temp.rrow(r)).rental_no || ' is out with the customer: Return it first. The invoice cannot move%',
    'E14 and to another store: ' || coalesce(m, 'saved'));
  -- E15 Out: another line added, and a note: saved, the rental unchanged.
  x := pg_temp.correct(inv, pg_temp.items(inv) || jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('strap'), 'quantity', 1)),
    '{}'::jsonb, 'T458 a strap too');
  perform pg_temp.check(x->>'success' = 'true' and (select count(*) from invoice_items where invoice_id = inv) = 2
      and (pg_temp.rrow(r)).status::text = 'active' and (pg_temp.rrow(r)).periods = 1 and jsonb_array_length(x->'rentals') = 0,
    'E15 a strap added beside a rental out is saved (before 458: refused); the rental is unchanged');
  x := pg_temp.correct(inv, pg_temp.items(inv), '{"notes": "T458 note"}'::jsonb, 'T458 a note');
  perform pg_temp.check(x->>'success' = 'true' and (select notes from invoices where id = inv) = 'T458 note',
    'E16 a note while the rental is out is saved');
  -- E17 A rental out that names no line keeps the old refusal.
  update rentals set invoice_item_id = null where id = r;
  m := pg_temp.msg(format('select pg_temp.correct(%L, %L::jsonb)', inv,
    (select jsonb_agg(case when q->>'kind' = 'product' then q || '{"quantity": 3}' else q end) from jsonb_array_elements(pg_temp.items(inv)) q)));
  perform pg_temp.check(m = 'Return or resolve the outstanding rental before changing its invoice allocation',
    'E17 a rental out naming no line keeps the refusal word for word: ' || coalesce(m, 'saved'));
end $$;

-- ═════ O Reopen ═════
do $$
declare inv uuid; r uuid; r2 uuid; w0 int; due0 date; x jsonb; ln uuid; it uuid;
begin
  -- O1 Cancelled while out, reopened before it came back: running again.
  inv := pg_temp.sale(1, 2); r := pg_temp.rent(inv);
  perform pg_temp.release(r);
  w0 := pg_temp.wh_qty(); due0 := (pg_temp.rrow(r)).expected_return_date;
  perform cancel_invoice_recorded(inv, 'T458 cancelled', gen_random_uuid());
  perform reopen_invoice(inv, 'T458 cancelled in error', gen_random_uuid());
  perform pg_temp.check((select status::text from invoices where id = inv) = 'paid'
      and (pg_temp.rrow(r)).status::text = 'active' and (pg_temp.rrow(r)).cancelled_at is null
      and (pg_temp.rrow(r)).expected_return_date = due0 and not rental_awaiting_return(r)
      and (select count(*) from rentals where invoice_id = inv) = 1 and pg_temp.wh_qty() = w0
      and pg_temp.audits(r, 'rental_running_again') = 1 and pg_temp.dash_out(inv) = 1,
    'O1 a rental cancelled while out runs again when its invoice is reopened: active, the same due date, no second rental, no stock moved, audited');
  x := return_rental_with_fee(r, 'good', true);
  perform pg_temp.check((pg_temp.rrow(r)).status::text = 'returned' and pg_temp.wh_qty() = w0 + 1,
    'O2 and it comes back with Return as any running rental');

  -- O3 Cancelled while out, received back, then reopened: one new waiting rental.
  inv := pg_temp.sale(2, 3); r := pg_temp.rent(inv);
  perform pg_temp.release(r);
  perform cancel_invoice_recorded(inv, 'T458 cancelled', gen_random_uuid());
  perform receive_returned_rental(r, null, 'good', 'T458 back', gen_random_uuid());
  perform reopen_invoice(inv, 'T458 cancelled in error', gen_random_uuid());
  select id into r2 from rentals where invoice_id = inv and id <> r;
  perform pg_temp.check((pg_temp.rrow(r)).status::text = 'cancelled' and (pg_temp.rrow(r)).stock_returned
      and r2 is not null and (pg_temp.rrow(r2)).status::text = 'awaiting_fulfilment' and (pg_temp.rrow(r2)).quantity = 2
      and (pg_temp.rrow(r2)).rental_fee = 180 and (select count(*) from rentals where invoice_id = inv) = 2
      and create_special_docs_for_invoice(inv) = 0,
    'O3 a rental cancelled while out and received back: reopening raises exactly one new waiting rental (2 machines, S$180), once');

  -- O4 A FOC invoice, cancelled and reopened: its rental is raised again.
  perform pg_temp.as_user('owner');
  inv := create_invoice(pg_temp.fx('store_a'), pg_temp.fx('cust_a'), null, jsonb_build_array(jsonb_build_object('kind', 'rental',
    'special_product_id', pg_temp.fx('sp'), 'quantity', 1, 'rental_rate_type', 'day', 'rental_periods', 2)));
  for it in select id from invoice_items where invoice_id = inv loop perform apply_line_foc(it, null, null, 'T458 giveaway'); end loop;
  perform confirm_foc_invoice(inv, null);
  r := pg_temp.rent(inv);
  perform cancel_invoice_recorded(inv, 'T458 giveaway undone', gen_random_uuid());
  perform reopen_invoice(inv, 'T458 giveaway after all', gen_random_uuid());
  perform pg_temp.check((select status::text from invoices where id = inv) = 'completed_foc'
      and (pg_temp.rrow(r)).status::text = 'cancelled'
      and (select count(*) from rentals where invoice_id = inv and status = 'awaiting_fulfilment' and rental_fee = 0) = 1,
    'O4 a FOC invoice cancelled and reopened raises its rental again (before 458: none)');

  -- O5 Refunded in full while out, reopened unpaid, then paid: running again at the payment.
  inv := pg_temp.sale(1, 2); r := pg_temp.rent(inv);
  perform pg_temp.release(r);
  perform pg_temp.refund(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.rline(inv), 'amount', 60)));
  perform reopen_invoice(inv, 'T458 refunded in error', gen_random_uuid());
  perform pg_temp.check((select status::text from invoices where id = inv) = 'unpaid' and rental_awaiting_return(r),
    'O5 refunded while out and reopened unpaid: still with the customer until it is paid');
  perform pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'), 'amount', 60)));
  perform pg_temp.check((select status::text from invoices where id = inv) = 'paid' and (pg_temp.rrow(r)).status::text = 'active'
      and (select count(*) from rentals where invoice_id = inv) = 1,
    'O6 paid again: the rental runs again, no second one');
end $$;

-- ═════ F Follows after a refund or a reopening (the review of 24 Oct 2026) ═════
-- A line split between a rental out and one waiting, as 458's reopening leaves it: 1 of 2 machines
-- refunded while out (split off), received back, the invoice cancelled, reopened and paid. The one
-- out runs again for one machine; the other machine waits again. Its invoice.
create function pg_temp.split_line() returns uuid language plpgsql as $$
declare inv uuid; a uuid; s uuid;
begin
  inv := pg_temp.sale(2, 2); a := pg_temp.rent(inv);
  perform pg_temp.release(a);
  perform pg_temp.refund(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.rline(inv), 'amount', 60)));
  select id into s from rentals where invoice_id = inv and id <> a;
  perform receive_returned_rental(s, null, 'good', 'T458 one back', gen_random_uuid());
  perform cancel_invoice_recorded(inv, 'T458 cancelled', gen_random_uuid());
  perform reopen_invoice(inv, 'T458 cancelled in error', gen_random_uuid());
  if (select status::text from invoices where id = inv) <> 'paid' then
    perform pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'),
      'amount', invoice_charge_total(inv) - invoice_net_received(inv))));
  end if;
  return inv;
end $$;
-- What happened before the reopening moved two minutes back and the reopening one: in one
-- transaction they share a clock, and a refund "since the reopening" must come after it.
create function pg_temp.reopened_earlier(p_inv uuid) returns void language sql as $$
  update invoice_refunds set created_at = created_at - interval '2 minutes' where invoice_id = p_inv;
  update rentals set cancelled_at = cancelled_at - interval '2 minutes' where invoice_id = p_inv and cancelled_at is not null;
  update audit_logs set created_at = created_at - interval '2 minutes'
   where table_name = 'rentals' and record_id in (select id from rentals where invoice_id = p_inv);
  update invoices set reopened_at = reopened_at - interval '1 minute' where id = p_inv;
$$;
-- The rentals of an invoice still running or waiting, and their machines.
create function pg_temp.live_units(p_inv uuid) returns int language sql as $$
  select coalesce(sum(quantity), 0)::int from rentals where invoice_id = p_inv
     and (rental_is_outstanding(status::text) or status::text = 'awaiting_fulfilment') $$;

do $$
declare inv uuid; r uuid; a uuid; b uuid; s uuid; ln uuid; x jsonb; m text; w0 int;
begin
  -- F1 1 of 2 machines waiting refunded (lowered to one), then the line extended to 3 days.
  inv := pg_temp.sale(2, 2); r := pg_temp.rent(inv); ln := pg_temp.rline(inv);
  perform pg_temp.refund(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', ln, 'amount', 60)));
  x := pg_temp.correct(inv, pg_temp.items(inv, '{"rental_periods": 3}'), '{}'::jsonb, 'T458 a day more');
  perform pg_temp.check((pg_temp.rrow(r)).quantity = 1 and (pg_temp.rrow(r)).periods = 3 and (pg_temp.rrow(r)).rental_fee = 90
      and (pg_temp.rrow(r)).rate_amount = 30 and (pg_temp.rrow(r)).status::text = 'awaiting_fulfilment'
      and (select count(*) from rentals where invoice_id = inv) = 1
      and x->'rentals'->0->>'what' like (pg_temp.rrow(r)).rental_no || ' (waiting for a warehouse): 1 × 3 days, S$90.00, due back %',
    'F1 a waiting rental lowered by a refund (1 of 2) keeps one machine when its line is extended (before: 2 machines, S$180): '
      || coalesce(x->'rentals'->0->>'what', ''));
  -- F2 Lowering that line to the machine kept is refused in words: the refund took the other off already.
  m := pg_temp.msg(format('select pg_temp.correct(%L, %L::jsonb)', inv, pg_temp.items(inv, '{"quantity": 1}')));
  perform pg_temp.check(m = (pg_temp.rrow(r)).rental_no || ': 1 of this line''s machines are refunded or on other rentals, '
        || 'so with 1 on the line it would hold none. Keep at least 2 on the line, or cancel ' || (pg_temp.rrow(r)).rental_no
        || ' on the Special page.'
      and (pg_temp.rrow(r)).quantity = 1,
    'F2 that line lowered to the machine kept is refused in words: ' || coalesce(m, 'saved'));
  -- F3 A machine added to that line (2 -> 3) goes on the waiting rental, the refunded one staying off.
  x := pg_temp.correct(inv, pg_temp.items(inv, '{"quantity": 3}'), '{}'::jsonb, 'T458 one more machine');
  perform pg_temp.check((pg_temp.rrow(r)).quantity = 2 and (pg_temp.rrow(r)).rental_fee = 180 and (pg_temp.rrow(r)).rate_amount = 60,
    'F3 a machine added to that line goes on the waiting rental: 2 machines at S$180 (two thirds of the line''s S$270)');

  -- F4 The split line: one machine out running again, the other waiting again.
  inv := pg_temp.split_line(); a := pg_temp.rent(inv);
  select id into s from rentals where invoice_id = inv and stock_returned;
  select id into b from rentals where invoice_id = inv and status::text = 'awaiting_fulfilment';
  perform pg_temp.check((select status::text from invoices where id = inv) = 'paid'
      and (pg_temp.rrow(a)).status::text = 'active' and (pg_temp.rrow(a)).quantity = 1
      and s is not null and b is not null and (pg_temp.rrow(b)).quantity = 1 and (pg_temp.rrow(b)).rental_fee = 60
      and pg_temp.live_units(inv) = 2,
    'F4 the split line: the rental out runs again for one machine, the other machine waits again (2 machines in all)');
  -- F5 Extended to 3 days: one machine each at half the line, 2 machines in all.
  x := pg_temp.correct(inv, pg_temp.items(inv, '{"rental_periods": 3}'), '{}'::jsonb, 'T458 a day more');
  perform pg_temp.check((pg_temp.rrow(a)).quantity = 1 and (pg_temp.rrow(a)).rental_fee = 90 and (pg_temp.rrow(a)).status::text = 'active'
      and (pg_temp.rrow(a)).periods = 3
      and (pg_temp.rrow(b)).quantity = 1 and (pg_temp.rrow(b)).rental_fee = 90 and (pg_temp.rrow(b)).periods = 3
      and pg_temp.live_units(inv) = 2 and jsonb_array_length(x->'rentals') = 2,
    'F5 the split line extended: the one out and the one waiting keep one machine each at S$90 (before: 3 machines, S$270): '
      || coalesce((x->'rentals')::text, ''));

  -- F6 The split line, one machine refunded since the reopening: the waiting one goes (no machine to bring back).
  inv := pg_temp.split_line(); a := pg_temp.rent(inv);
  select id into b from rentals where invoice_id = inv and status::text = 'awaiting_fulfilment';
  perform pg_temp.reopened_earlier(inv);
  perform pg_temp.refund(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.rline(inv), 'amount', 60)), 'T458 one machine back');
  perform pg_temp.check((pg_temp.rrow(b)).status::text = 'cancelled' and (pg_temp.rrow(b)).notes like '%Cancelled (refunded): T458 one machine back%'
      and (pg_temp.rrow(a)).status::text = 'active' and (pg_temp.rrow(a)).quantity = 1 and pg_temp.live_units(inv) = 1
      and jsonb_array_length(invoice_rentals_awaiting_return(inv)) = 0,
    'F6 the split line, 1 of 2 refunded since the reopening: the waiting machine is cancelled, the one out runs on (1 machine left, before: 2)');
  -- F7 The same refund answered "still taking" for the waiting one: the one out ends instead.
  inv := pg_temp.split_line(); a := pg_temp.rent(inv);
  select id into b from rentals where invoice_id = inv and status::text = 'awaiting_fulfilment';
  perform pg_temp.reopened_earlier(inv);
  perform pg_temp.refund(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.rline(inv), 'amount', 60,
    'waiting', jsonb_build_array(jsonb_build_object('doc_id', b, 'still_taking', true)))), 'T458 the one out back');
  perform pg_temp.check((pg_temp.rrow(b)).status::text = 'awaiting_fulfilment' and (pg_temp.rrow(b)).quantity = 1
      and (pg_temp.rrow(a)).status::text = 'cancelled' and rental_awaiting_return(a) and pg_temp.live_units(inv) = 1
      and jsonb_array_length(invoice_rentals_awaiting_return(inv)) = 1,
    'F7 answered "still taking" for the waiting one: the one out ends (to be received), the waiting one stays');

  -- F8 A strap added unpaid beside a waiting rental: the rental is held until the invoice is paid in full.
  inv := pg_temp.sale(1, 2); r := pg_temp.rent(inv);
  x := pg_temp.correct(inv, pg_temp.items(inv) || jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('strap'), 'quantity', 1)),
    '{}'::jsonb, 'T458 a strap too');
  w0 := pg_temp.wh_qty();
  m := pg_temp.msg(format('select pg_temp.release(%L)', r));
  perform pg_temp.check(m like (pg_temp.rrow(r)).rental_no || ' cannot be released yet: its invoice % has S$20.00 owing.%'
      and pg_temp.wh_qty() = w0 and jsonb_array_length(x->'rentals') = 0,
    'F8 a waiting rental beside a strap added unpaid is held until the S$20 is paid: ' || coalesce(m, 'released'));
  perform pay_invoice(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'), 'amount', 20)));
  perform pg_temp.release(r);
  perform pg_temp.check((pg_temp.rrow(r)).status::text = 'active' and pg_temp.wh_qty() = w0 - 1,
    'F9 paid in full, it is released');
end $$;

-- ═════ D 'Due back' blank ═════
do $$
declare inv uuid; due_m date; due_w date; due_y date; due_t date;
begin
  inv := pg_temp.sale(1, 1, 'month', false, date '2027-01-31');
  due_m := (pg_temp.rrow(pg_temp.rent(inv))).expected_return_date;
  inv := pg_temp.sale(1, 2, 'week', false, date '2027-03-01');
  due_w := (pg_temp.rrow(pg_temp.rent(inv))).expected_return_date;
  inv := pg_temp.sale(1, 1, 'year', false, date '2028-02-29');
  due_y := (pg_temp.rrow(pg_temp.rent(inv))).expected_return_date;
  inv := pg_temp.sale(1, 3);
  due_t := (pg_temp.rrow(pg_temp.rent(inv))).expected_return_date;
  perform pg_temp.check(due_m = date '2027-02-28' and due_w = date '2027-03-15' and due_y = date '2029-02-28'
      and due_t = sg_today() + 3,
    format('D1 Due back blank is the start + the periods by rate type: a month from 31 Jan %s, 2 weeks from 1 Mar %s, a year from 29 Feb %s, 3 days from today %s',
      due_m, due_w, due_y, due_t));
  -- The read-only list for the Owner: rentals whose line had no Due back and
  -- whose due date is not the start + periods by rate type.
  inv := pg_temp.sale(1, 2, 'month', false, date '2027-05-10');
  update rentals set expected_return_date = sg_today() + 2 where invoice_id = inv;
  perform pg_temp.check((select count(*) from rentals r join invoices i on i.id = r.invoice_id
                          left join invoice_items ii on ii.id = r.invoice_item_id
                         where r.invoice_id is not null and ii.rental_return_date is null
                           and r.expected_return_date is distinct from (r.start_date + case r.rate_type
                                 when 'day' then make_interval(days => r.periods) when 'week' then make_interval(days => 7 * r.periods)
                                 when 'month' then make_interval(months => r.periods) else make_interval(years => r.periods) end)::date
                           and i.store_id = pg_temp.fx('store_a') and r.rate_type::text = 'month') = 1,
    'D2 the read-only list finds a rental saved the old way (a 2-month rental due back today + 2 days)');
end $$;

-- ═════ M 458 twice ═════
\if :{?skip_install}
\else
select pg_temp.check(not exists (select 1 from m458 m left join pg_temp.fn_md5s() f on f.fn = m.fn where f.fn is null or f.md5 <> m.md5)
    and (select count(*) from pg_temp.fn_md5s()) = (select count(*) from m458),
  'M1 running 458 a second time changed no function');
select pg_temp.check((select coalesce(array_agg(m.fn order by m.fn), '{}') from m458 m left join b458 b on b.fn = m.fn
                       where b.fn is null or b.md5 <> m.md5)
                     = array['correct_invoice(uuid,jsonb,jsonb,text,uuid)', 'create_special_docs_for_invoice(uuid)',
                             'fulfil_special_doc(text,uuid,uuid,text)',
                             'invoice_rental_correction_check(uuid,jsonb,uuid,uuid)', 'invoice_rentals_follow_lines(uuid,jsonb,text)',
                             'preview_invoice_correction(uuid,jsonb)', 'rental_end_on_refund(uuid,integer,text)',
                             'rentals_follow_refund(uuid,jsonb,text)', 'reopen_invoice(uuid,text,uuid)',
                             'settle_waiting_special_docs_on_refund(uuid,jsonb,text)']
    and (select count(*) from m458) = (select count(*) from b458) + 4
    and not exists (select 1 from b458 b left join m458 m on m.fn = b.fn where m.fn is null),
  'M2 its first run changed the six and added the four (none dropped)');
select pg_temp.check((select before = after1 from r458),
  'M3 458''s self-test left no row (every table of public and auth counts the same before and after it)');
\endif

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All 458 checks passed.';
end $$;
rollback;
