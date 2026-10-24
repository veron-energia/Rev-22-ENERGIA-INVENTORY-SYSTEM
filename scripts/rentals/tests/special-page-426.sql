-- 426 (audit findings SALES-EXTRAS-7, -12 and -16): the Special page's server side.
--
--   1. Change rental terms (update_pending_rental) changes only a rental still
--      waiting for a warehouse, as the waiting list shows it: not one released
--      from a store or a warehouse, returned, cancelled, or whose invoice was
--      cancelled. With no return date given, "Due back" is worked out again
--      from the start and the periods (days, weeks, calendar months, years; a
--      month after 31 Jan is 28 Feb); a date given is kept, never before the
--      start. An active Owner or Manager only: anyone else, an Admin and a
--      deactivated Manager included, is refused with 42501. The waiting list
--      then shows the new terms.
--   1b. The owner, 18 Oct 2026 ("Keep the same discount"): a change of the
--      quantity, the rate type or the periods keeps the invoice line's FOC
--      share, or its amount or percentage off, on the new list fee, never
--      below S$0; a change of dates alone keeps the fee as sold (difference
--      0). While the rental's terms are the line's, the fee before is what
--      the line charges, also after a correction of the line's price alone
--      (1 of 2 made FOC on the paid invoice). The audit row has the old and
--      new fee.
--   2. A special product's description: an emptied one clears it, one left
--      out (null) stays, one given is saved trimmed. Owner or Manager only.
--   3. The old Special page paths are the service role's alone: an Owner
--      calling create_special_sale, create_rental, pay_rental,
--      activate_rental, cancel_rental, cancel_special_sale or
--      pay_special_with_credit is refused with 42501, and nothing is written.
--   4. The Rentals tab's "Receive returned item" (the owner, 10 Oct 2026)
--      makes exactly the call the page makes: a rental cancelled while still
--      with the customer goes back to the store it came from (417).
--
-- Needs 417. With psql -v mig=supabase/426_special_rentals_and_orders.sql
-- it installs 426 after "begin;", twice (the second run must change
-- nothing). Disposable database only; everything is rolled back. Every name,
-- phone and number here is invented (@sig.invalid).
--   psql -v ON_ERROR_STOP=1 -v mig=supabase/426_special_rentals_and_orders.sql -f scripts/rentals/tests/special-page-426.sql
\set ON_ERROR_STOP on
begin;
\if :{?mig}
\i :mig
create temp table t426_fp as
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) as fp
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f';
\i :mig
do $$
begin
  if (select fp from t426_fp) is distinct from (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text))
                                                  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f') then
    raise exception 'FAIL 0: a second run of 426 changed a function'; end if;
  raise notice 'PASS 0: 426 installs, and a second run changes nothing';
end $$;
\endif

create temp table t426(k text primary key, id uuid);
create function pg_temp.t426_id(p_k text) returns uuid language sql as $f$ select id from t426 where k = p_k $f$;
create function pg_temp.t426_as(p_k text) returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.t426_id(p_k), 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', pg_temp.t426_id(p_k)::text, true);
end $f$;
-- Runs p_sql as the signed-in login p_k (role authenticated, as the page
-- does) and returns the SQLSTATE and message it was refused with, or 'ok'.
create function pg_temp.t426_try(p_k text, p_sql text) returns text language plpgsql as $f$
declare v_state text; v_msg text;
begin
  perform pg_temp.t426_as(p_k);
  begin
    set local role authenticated;
    execute p_sql;
    reset role;
    return 'ok';
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    reset role;
    return v_state || ' ' || v_msg;
  end;
end $f$;

do $$
declare o uuid := gen_random_uuid(); m uuid := gen_random_uuid(); m2 uuid := gen_random_uuid();
  a uuid := gen_random_uuid(); s uuid := gen_random_uuid();
  sa uuid; sb uuid; wh uuid; c uuid; pm uuid; p uuid; sp uuid;
begin
  insert into auth.users(id, email) values (o, 't426-owner@sig.invalid'), (m, 't426-manager@sig.invalid'),
    (m2, 't426-gone@sig.invalid'), (a, 't426-admin@sig.invalid'), (s, 't426-staff@sig.invalid');
  insert into profiles(id, full_name, email, role, is_active) values
    (o, 'T426 Owner', 't426-owner@sig.invalid', 'owner', true),
    (m, 'T426 Manager', 't426-manager@sig.invalid', 'manager', true),
    (m2, 'T426 Former Manager', 't426-gone@sig.invalid', 'manager', false),
    (a, 'T426 Admin', 't426-admin@sig.invalid', 'admin', true),
    (s, 'T426 Staff', 't426-staff@sig.invalid', 'staff', true);
  insert into t426 values ('owner', o), ('manager', m), ('gone', m2), ('admin', a), ('staff', s);
  perform pg_temp.t426_as('owner');
  insert into stores(name, code, country_code) values ('T426 Store A', 'T426A', 'SG') returning id into sa;
  insert into stores(name, code, country_code) values ('T426 Store B', 'T426B', 'SG') returning id into sb;
  insert into warehouses(name, code) values ('T426 Warehouse', 'T426W') returning id into wh;
  insert into user_store_assignments(user_id, store_id) values (m, sa), (s, sa);
  insert into customers(full_name, phone) values ('T426 Renter', '+61491570156') returning id into c;
  insert into payment_methods(name, is_active) values ('T426 Cash', true) returning id into pm;
  insert into products(name, sku, product_type) values ('T426 Machine', 'T426-M', 'own') returning id into p;
  insert into warehouse_inventory(warehouse_id, product_id, current_qty) values (wh, p, 10);
  insert into store_inventory(store_id, product_id, current_qty) values (sb, p, 4);
  -- S$30 a day, S$150 a week, S$400 a month, S$3,000 a year.
  sp := upsert_special_product_from_product(null, p, 0, 30, 150, 400, 3000, 5, null, true);
  insert into t426 values ('store_a', sa), ('store_b', sb), ('warehouse', wh), ('customer', c), ('cash', pm),
    ('product', p), ('special', sp);
end $$;

-- A paid invoice of one two-day rental: the rental waits for a warehouse.
create function pg_temp.t426_rental() returns uuid language plpgsql as $f$
declare v_inv uuid; v_r uuid;
begin
  perform pg_temp.t426_as('owner');
  v_inv := create_invoice(pg_temp.t426_id('store_a'), pg_temp.t426_id('customer'), null,
    jsonb_build_array(jsonb_build_object('kind', 'rental', 'special_product_id', pg_temp.t426_id('special'),
      'quantity', 1, 'rental_rate_type', 'day', 'rental_periods', 2)));
  perform pay_invoice(v_inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t426_id('cash'),
    'amount', invoice_charge_total(v_inv))));
  select id into v_r from rentals where invoice_id = v_inv;
  if v_r is null or (select status::text from rentals where id = v_r) <> 'awaiting_fulfilment' then
    raise exception 'Fixture: the paid rental is not waiting for a warehouse'; end if;
  return v_r;
end $f$;
create function pg_temp.t426_change(p_k text, p_rental uuid, p_qty int, p_rate text, p_periods int,
  p_start date, p_due date) returns text language sql as $f$
  select pg_temp.t426_try(p_k, format('select public.update_pending_rental(%L::uuid, %s, %L::special_rate_type, %s, %L::date, %L::date, null)',
    p_rental, coalesce(p_qty::text, 'null'), p_rate, coalesce(p_periods::text, 'null'), p_start, p_due))
$f$;

-- ===== 1. Change rental terms: only while waiting; "Due back" follows =====
do $$
declare r uuid; r2 uuid; v text; q jsonb;
begin
  r := pg_temp.t426_rental();
  -- Days, from a new start, with no date given.
  v := pg_temp.t426_change('manager', r, 1, 'day', 3, date '2027-01-31', null);
  if v <> 'ok' then raise exception 'FAIL 1: a Manager could not change a waiting rental: %', v; end if;
  if (select (start_date, expected_return_date, rental_fee) from rentals where id = r)
     is distinct from (date '2027-01-31', date '2027-02-03', 90.00::numeric(12,2)) then
    raise exception 'FAIL 1: 3 days from 31 Jan 2027 at S$30: %', (select (start_date, expected_return_date, rental_fee) from rentals where id = r); end if;
  -- A calendar month from 31 Jan is the last day of February (28 Feb 2027, 29 Feb 2028).
  perform pg_temp.t426_change('owner', r, 1, 'month', 1, null, null);
  if (select (expected_return_date, rental_fee) from rentals where id = r) is distinct from (date '2027-02-28', 400.00::numeric(12,2)) then
    raise exception 'FAIL 1: a month from 31 Jan 2027 is not 28 Feb: %', (select expected_return_date from rentals where id = r); end if;
  perform pg_temp.t426_change('owner', r, 1, 'month', 1, date '2028-01-31', null);
  if (select expected_return_date from rentals where id = r) is distinct from date '2028-02-29' then
    raise exception 'FAIL 1: a month from 31 Jan 2028 is not 29 Feb'; end if;
  perform pg_temp.t426_change('owner', r, 2, 'week', 2, null, null);
  if (select (expected_return_date, rental_fee) from rentals where id = r) is distinct from (date '2028-02-14', 600.00::numeric(12,2)) then
    raise exception 'FAIL 1: 2 weeks x 2 units: %', (select (expected_return_date, rental_fee) from rentals where id = r); end if;
  perform pg_temp.t426_change('owner', r, 1, 'year', 1, date '2028-02-29', null);
  if (select expected_return_date from rentals where id = r) is distinct from date '2029-02-28' then
    raise exception 'FAIL 1: a year from 29 Feb 2028 is not 28 Feb 2029'; end if;
  -- Only the periods changed: the due date moves with them.
  perform pg_temp.t426_change('owner', r, null, 'day', 10, date '2027-03-01', null);
  if (select expected_return_date from rentals where id = r) is distinct from date '2027-03-11' then
    raise exception 'FAIL 1: 10 days from 1 Mar 2027 is not 11 Mar'; end if;
  -- A date given is kept; one before the start is refused.
  perform pg_temp.t426_change('owner', r, null, 'day', 10, null, date '2027-03-20');
  if (select expected_return_date from rentals where id = r) is distinct from date '2027-03-20' then
    raise exception 'FAIL 1: a typed "Due back" was not kept'; end if;
  v := pg_temp.t426_change('owner', r, null, 'day', 10, null, date '2027-02-28');
  if v not like 'P0001 The return date cannot be before the start date' then
    raise exception 'FAIL 1: a return date before the (kept) start was taken: %', v; end if;
  v := pg_temp.t426_change('owner', r, null, 'day', 1, date '2027-04-10', date '2027-04-01');
  if v not like 'P0001 The return date cannot be before the start date' then
    raise exception 'FAIL 1: a return date before a new start was taken: %', v; end if;
  -- The answer names the due date, and the audit row the dates before and after.
  perform pg_temp.t426_as('owner');
  q := update_pending_rental(r, 1, 'day', 2, date '2027-05-01', null, null);
  if q->>'expected_return_date' is distinct from '2027-05-03' or (q->>'rental_fee')::numeric <> 60 then
    raise exception 'FAIL 1: the answer was %', q; end if;
  if not exists (select 1 from audit_logs where record_id = r and action = 'pending_rental_edited'
                  and new_data->>'due_now' = '2027-05-03' and new_data->>'due_was' = '2027-03-20'
                  and new_data->>'start_date' = '2027-05-01') then
    raise exception 'FAIL 1: the audit row does not record the due date before and after'; end if;
  -- The waiting list shows the new terms.
  if (select (l.periods, l.expected_return_date, l.rental_fee) from special_docs_awaiting_fulfilment() l where l.doc_id = r)
     is distinct from (2, date '2027-05-03', 60.00::numeric) then
    raise exception 'FAIL 1: the waiting list does not show the new terms'; end if;

  -- Who: an active Owner or Manager only.
  foreach v in array array['staff', 'admin', 'gone'] loop
    if pg_temp.t426_change(v, r, 3, 'day', 3, null, null) not like '42501 %' then
      raise exception 'FAIL 1: % was not refused with 42501: %', v, pg_temp.t426_change(v, r, 3, 'day', 3, null, null); end if;
  end loop;
  if (select (quantity, periods) from rentals where id = r) is distinct from (1, 2) then
    raise exception 'FAIL 1: a refused caller changed the rental'; end if;

  -- Released from a store: no longer waiting.
  perform pg_temp.t426_as('owner');
  perform fulfil_special_doc('rental', r, pg_temp.t426_id('store_b'), 'store');
  v := pg_temp.t426_change('owner', r, 3, 'day', 5, null, null);
  if v not like 'P0001 This rental has already been released%' then
    raise exception 'FAIL 1: a rental released from a store was changed: %', v; end if;
  -- Returned, cancelled (no warehouse, no store): not waiting either.
  update rentals set warehouse_id = null, source_store_id = null where id = r;
  update rentals set status = 'returned', stock_returned = true where id = r;
  v := pg_temp.t426_change('owner', r, 3, 'day', 5, null, null);
  if v not like 'P0001 % is not waiting for a warehouse any more (it is returned)%' then
    raise exception 'FAIL 1: a returned rental was changed: %', v; end if;
  update rentals set status = 'cancelled' where id = r;
  v := pg_temp.t426_change('owner', r, 3, 'day', 5, null, null);
  if v not like 'P0001 % is not waiting for a warehouse any more (it is cancelled)%' then
    raise exception 'FAIL 1: a cancelled rental was changed: %', v; end if;
  -- Still marked waiting, but its invoice was cancelled: refused with why.
  r2 := pg_temp.t426_rental();
  update invoices set status = 'cancelled' where id = (select invoice_id from rentals where id = r2);
  v := pg_temp.t426_change('owner', r2, 3, 'day', 5, null, null);
  if v not like 'P0001 % cannot be changed: its invoice % was cancelled.' then
    raise exception 'FAIL 1: a rental whose invoice was cancelled was changed: %', v; end if;
  if (select (quantity, rental_fee) from rentals where id = r2) is distinct from (1, 60.00::numeric(12,2)) then
    raise exception 'FAIL 1: a refused change was saved'; end if;
  raise notice 'PASS 1: only a rental still waiting is changed; "Due back" follows the start, rate and periods (31 Jan + 1 month = 28 Feb), a typed date is kept, never before the start; Owner or Manager only (42501 for Staff, Admin, a deactivated Manager); the waiting list and the audit row follow';
end $$;

-- ===== 1b. The same discount as sold; a change of dates alone keeps the fee =====
-- The owner, 18 Oct 2026 ("Keep the same discount"): a change of the
-- quantity, the rate type or the periods prices the new terms at the list
-- rate less the same FOC share, or the same amount or percentage off, as the
-- invoice line sold it, never below S$0. A change of dates alone keeps the
-- fee as sold (before 426 it asked for S$949 on a free rental). A line
-- whose price was corrected afterwards is followed. The same cases are in
-- scripts/special/tests/rental-terms.test.mjs (the page's preview).
create function pg_temp.t426_sold(p_line jsonb) returns uuid language plpgsql as $f$
declare v_inv uuid; v_r uuid;
begin
  perform pg_temp.t426_as('owner');
  v_inv := create_invoice(pg_temp.t426_id('store_a'), pg_temp.t426_id('customer'), null,
    jsonb_build_array(jsonb_build_object('kind', 'rental', 'special_product_id', pg_temp.t426_id('special')) || p_line));
  perform pay_invoice(v_inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.t426_id('cash'),
    'amount', invoice_charge_total(v_inv))));
  select id into v_r from rentals where invoice_id = v_inv;
  if v_r is null or (select status::text from rentals where id = v_r) <> 'awaiting_fulfilment' then
    raise exception 'Fixture: the paid rental is not waiting for a warehouse'; end if;
  return v_r;
end $f$;
-- One change as the Owner: the answer's (fee, invoiced, difference) must be
-- p_want, and the rental's fee what the answer says.
create function pg_temp.t426_fee(p_case text, p_rental uuid, p_qty int, p_rate text, p_periods int, p_start date,
  p_want numeric[], p_how text default null) returns jsonb language plpgsql as $f$
declare q jsonb;
begin
  perform pg_temp.t426_as('owner');
  q := update_pending_rental(p_rental, p_qty, p_rate::special_rate_type, p_periods, p_start, null, null);
  if array[(q->>'rental_fee')::numeric, (q->>'invoiced_fee')::numeric, (q->>'difference')::numeric] is distinct from p_want
     or (select rental_fee from rentals where id = p_rental) is distinct from p_want[1]
     or q->>'discount_kept' is distinct from p_how then
    raise exception 'FAIL 1b (%): wanted fee, invoiced, difference % (%), the answer was %', p_case, p_want, p_how, q; end if;
  return q;
end $f$;
-- Sold as p_line, then the Owner corrects the paid invoice's line to p_fix
-- (its price alone: the same quantity, rate type and periods). The rental
-- keeps the fee it was raised at (before 458) or takes the line's (458: a
-- waiting rental follows its corrected line); p_line_total is what the line
-- now holds. Either way the fee as sold is read from the line below.
create function pg_temp.t426_corrected(p_line jsonb, p_fix jsonb, p_line_total numeric) returns uuid language plpgsql as $f$
declare v_r uuid; v_inv uuid; v_li uuid; v_fee numeric;
begin
  v_r := pg_temp.t426_sold(p_line);
  select invoice_id, invoice_item_id, rental_fee into v_inv, v_li, v_fee from rentals where id = v_r;
  perform pg_temp.t426_as('owner');
  perform correct_invoice(v_inv, jsonb_build_array(jsonb_build_object('invoice_item_id', v_li, 'kind', 'rental',
    'special_product_id', pg_temp.t426_id('special')) || p_line || p_fix), '{}'::jsonb, 'T426 sample');
  if (select line_total from invoice_items where id = v_li) is distinct from p_line_total
     or ((select (status::text, rental_fee, invoice_item_id) from rentals where id = v_r)
           is distinct from ('awaiting_fulfilment'::text, v_fee, v_li)
         and (select (status::text, rental_fee, invoice_item_id) from rentals where id = v_r)
           is distinct from ('awaiting_fulfilment'::text, p_line_total, v_li))
     or public.special_doc_invoice_problem(v_inv, v_li) is not null then
    raise exception 'Fixture: the corrected rental is % on a line of %', (select (status, rental_fee, invoice_item_id) from rentals where id = v_r),
      (select (line_total, foc_quantity, line_discount) from invoice_items where id = v_li); end if;
  return v_r;
end $f$;

do $$
declare inv uuid; r uuid; rf uuid; ra uuid; rz uuid; rp uuid; rr uuid; rc uuid; q jsonb; v text;
begin
  perform pg_temp.t426_as('owner');
  -- ── Part FOC: two machines for two days, one of them FOC: S$60 paid, not S$120.
  r := pg_temp.t426_sold(jsonb_build_object('quantity', 2, 'foc_quantity', 1, 'foc_reason', 'T426 sample',
    'rental_rate_type', 'day', 'rental_periods', 2));
  if (select (quantity, rental_fee, rate_amount) from rentals where id = r)
     is distinct from (2, 60.00::numeric(12,2), 30.00::numeric(12,2)) then
    raise exception 'Fixture: the part-FOC rental is %', (select (status, quantity, rental_fee, rate_amount) from rentals where id = r); end if;
  -- New dates with the same quantity, rate and periods (what the page sends).
  perform pg_temp.t426_fee('part FOC, dates', r, 2, 'day', 2, date '2027-06-01', array[60, 60, 0]);
  if (select (rental_fee, rate_amount, start_date, expected_return_date) from rentals where id = r)
     is distinct from (60.00::numeric(12,2), 30.00::numeric(12,2), date '2027-06-01', date '2027-06-03') then
    raise exception 'FAIL 1b: the part-FOC rental was saved as %', (select (rental_fee, rate_amount, start_date, expected_return_date) from rentals where id = r); end if;
  -- A new start alone, the rest left out (null): the fee stays, "Due back" follows.
  q := update_pending_rental(r, null, null, null, date '2027-06-10', null, null);
  if (q->>'difference')::numeric <> 0 or (select (rental_fee, expected_return_date) from rentals where id = r)
     is distinct from (60.00::numeric(12,2), date '2027-06-12') then
    raise exception 'FAIL 1b: a new start alone priced it again or did not move "Due back": %', q; end if;
  -- 3 days: S$180 at the list rate, half FOC as sold: S$90, S$30 more.
  q := pg_temp.t426_fee('part FOC, periods', r, 2, 'day', 3, null, array[90, 60, 30], 'the same FOC share as sold (1 of 2 free)');
  if (q->>'list_fee')::numeric <> 180 or (select (rate_amount, periods) from rentals where id = r) is distinct from (30.00::numeric(12,2), 3) then
    raise exception 'FAIL 1b: the list fee or the rate is not the list rate''s: %', q; end if;
  -- 3 machines: S$270, half: S$135, S$45 more than the S$90 it now is.
  perform pg_temp.t426_fee('part FOC, quantity', r, 3, 'day', 3, null, array[135, 90, 45], 'the same FOC share as sold (1 of 2 free)');
  -- A week instead of days: 3 x S$150, half: S$225.
  perform pg_temp.t426_fee('part FOC, rate type', r, 3, 'week', 1, null, array[225, 135, 90], 'the same FOC share as sold (1 of 2 free)');
  -- Then the dates alone: S$225 stays.
  perform pg_temp.t426_fee('part FOC, dates after', r, 3, 'week', 1, date '2027-07-01', array[225, 225, 0]);
  if (select expected_return_date from rentals where id = r) is distinct from date '2027-07-08' then
    raise exception 'FAIL 1b: a week from 1 Jul is not 8 Jul'; end if;
  -- The audit row: the terms and fee before (old), the fee after, the list fee and the discount kept (new).
  if not exists (select 1 from audit_logs where record_id = r and action = 'pending_rental_edited'
                  and old_data->>'rate_type' = 'day' and (old_data->>'rental_fee')::numeric = 135
                  and (new_data->>'fee_was')::numeric = 135 and (new_data->>'fee_now')::numeric = 225
                  and (new_data->>'list_fee')::numeric = 450
                  and new_data->>'discount_kept' = 'the same FOC share as sold (1 of 2 free)') then
    raise exception 'FAIL 1b: the audit row does not record the old and new fee'; end if;
  -- The waiting list shows the new fee.
  if (select l.rental_fee from special_docs_awaiting_fulfilment() l where l.doc_id = r) is distinct from 225.00::numeric then
    raise exception 'FAIL 1b: the waiting list does not show the new fee'; end if;
  -- Part FOC with odd cents: 3 machines for a month, 2 of them FOC (S$400
  -- paid), then 1 machine: S$400 less 2/3 of it (S$266.67, to the cent): S$133.33.
  rr := pg_temp.t426_sold(jsonb_build_object('quantity', 3, 'foc_quantity', 2, 'foc_reason', 'T426 sample',
    'rental_rate_type', 'month', 'rental_periods', 1));
  perform pg_temp.t426_fee('part FOC, odd cents', rr, 1, 'month', 1, null, array[133.33, 400, -266.67], 'the same FOC share as sold (2 of 3 free)');

  -- ── The line's price corrected afterwards (the 18 Oct review): two machines
  -- for two days, S$120, then the Owner corrects the invoice to 1 of 2 FOC
  -- (S$60). The rental still carries S$120; what it charges is the line's S$60.
  rc := pg_temp.t426_corrected(jsonb_build_object('quantity', 2, 'rental_rate_type', 'day', 'rental_periods', 2),
    jsonb_build_object('foc_quantity', 1, 'foc_reason', 'T426 sample'), 60);
  perform pg_temp.t426_fee('corrected to part FOC, dates', rc, 2, 'day', 2, date '2027-10-01', array[60, 60, 0]);
  perform pg_temp.t426_fee('corrected to part FOC, periods', rc, 2, 'day', 3, null, array[90, 60, 30], 'the same FOC share as sold (1 of 2 free)');
  -- The same, the periods changed first: S$30 to collect, not S$30 to refund.
  rc := pg_temp.t426_corrected(jsonb_build_object('quantity', 2, 'rental_rate_type', 'day', 'rental_periods', 2),
    jsonb_build_object('foc_quantity', 1, 'foc_reason', 'T426 sample'), 60);
  perform pg_temp.t426_fee('corrected to part FOC, periods first', rc, 2, 'day', 3, null, array[90, 60, 30], 'the same FOC share as sold (1 of 2 free)');

  -- ── Free: the whole line FOC, then Confirm FOC: S$0 stays S$0, whatever changes.
  inv := create_invoice(pg_temp.t426_id('store_a'), pg_temp.t426_id('customer'), null,
    jsonb_build_array(jsonb_build_object('kind', 'rental', 'special_product_id', pg_temp.t426_id('special'),
      'quantity', 1, 'is_foc', true, 'foc_reason', 'T426 sample', 'rental_rate_type', 'month', 'rental_periods', 1)));
  perform confirm_foc_invoice(inv, 'T426 sample');
  select id into rf from rentals where invoice_id = inv;
  if (select (status::text, rental_fee, rate_amount) from rentals where id = rf)
     is distinct from ('awaiting_fulfilment'::text, 0.00::numeric(12,2), 0.00::numeric(12,2)) then
    raise exception 'Fixture: the free rental is %', (select (status, rental_fee, rate_amount) from rentals where id = rf); end if;
  v := pg_temp.t426_change('manager', rf, 1, 'month', 1, date '2027-07-01', date '2027-08-01');
  if v <> 'ok' then raise exception 'FAIL 1b: a Manager could not move the free rental: %', v; end if;
  if (select (rental_fee, rate_amount, start_date, expected_return_date) from rentals where id = rf)
     is distinct from (0.00::numeric(12,2), 0.00::numeric(12,2), date '2027-07-01', date '2027-08-01') then
    raise exception 'FAIL 1b: the free rental was saved as %', (select (rental_fee, rate_amount, start_date, expected_return_date) from rentals where id = rf); end if;
  if not exists (select 1 from audit_logs where record_id = rf and action = 'pending_rental_edited'
                  and (new_data->>'fee_was')::numeric = 0 and (new_data->>'fee_now')::numeric = 0) then
    raise exception 'FAIL 1b: the audit row does not show the fee kept at S$0'; end if;
  perform pg_temp.t426_fee('free, quantity', rf, 2, 'month', 1, null, array[0, 0, 0], 'FOC, as sold');
  perform pg_temp.t426_fee('free, periods', rf, 2, 'month', 3, null, array[0, 0, 0], 'FOC, as sold');
  q := pg_temp.t426_fee('free, rate type', rf, 2, 'year', 1, null, array[0, 0, 0], 'FOC, as sold');
  if (q->>'list_fee')::numeric <> 6000 then raise exception 'FAIL 1b: the free rental''s list fee is %', q; end if;

  -- ── A fixed amount off: two machines for two days, S$120 less S$25: S$95
  -- charged. The invoice raises the rental at the line's value before its
  -- discount (S$120), so what it charges is the S$95 sold.
  ra := pg_temp.t426_sold(jsonb_build_object('quantity', 2, 'rental_rate_type', 'day', 'rental_periods', 2,
    'line_discount_type', 'manual', 'line_discount_amount', 25, 'line_discount_reason', 'T426 sample'));
  if (select rental_fee from rentals where id = ra) is distinct from 120.00::numeric(12,2) then
    raise exception 'Fixture: the S$25-off rental is %', (select rental_fee from rentals where id = ra); end if;
  -- The dates alone: the fee as sold, S$95; nothing to collect.
  perform pg_temp.t426_fee('amount off, dates', ra, 2, 'day', 2, date '2027-08-01', array[95, 95, 0]);
  if not exists (select 1 from audit_logs where record_id = ra and action = 'pending_rental_edited'
                  and (old_data->>'rental_fee')::numeric = 120 and (new_data->>'fee_was')::numeric = 95
                  and (new_data->>'fee_now')::numeric = 95 and new_data->>'list_fee' is null) then
    raise exception 'FAIL 1b: the audit row of the dates alone does not record S$120 on record, S$95 as sold'; end if;
  -- 3 days: S$180 less the same S$25: S$155, S$60 more than the S$95 sold.
  perform pg_temp.t426_fee('amount off, periods', ra, 2, 'day', 3, null, array[155, 95, 60], 'the same S$25.00 off as sold');
  -- 1 machine: S$90 less S$25: S$65, S$90 less.
  perform pg_temp.t426_fee('amount off, quantity', ra, 1, 'day', 3, null, array[65, 155, -90], 'the same S$25.00 off as sold');
  -- 3 weeks: S$450 less S$25: S$425.
  perform pg_temp.t426_fee('amount off, rate type', ra, 1, 'week', 3, null, array[425, 65, 360], 'the same S$25.00 off as sold');
  -- Never below S$0: a week less S$140 (S$10 charged), then one day: S$30 less S$140 is S$0.
  rz := pg_temp.t426_sold(jsonb_build_object('quantity', 1, 'rental_rate_type', 'week', 'rental_periods', 1,
    'line_discount_type', 'manual', 'line_discount_amount', 140, 'line_discount_reason', 'T426 sample'));
  perform pg_temp.t426_fee('amount off, never below 0', rz, 1, 'day', 1, null, array[0, 10, -10], 'the same S$140.00 off as sold');

  -- ── A percentage off: one machine for a week, S$150 less 12.5% (S$18.75): S$131.25 charged.
  rp := pg_temp.t426_sold(jsonb_build_object('quantity', 1, 'rental_rate_type', 'week', 'rental_periods', 1,
    'line_discount_type', 'percentage', 'line_discount_percent', 12.5, 'line_discount_reason', 'T426 sample'));
  -- 2 machines: S$300 less 12.5%: S$262.50, S$131.25 more.
  perform pg_temp.t426_fee('percent off, quantity', rp, 2, 'week', 1, null, array[262.50, 131.25, 131.25], 'the same 12.5% off as sold');
  -- 3 weeks: S$900 less 12.5%: S$787.50.
  perform pg_temp.t426_fee('percent off, periods', rp, 2, 'week', 3, null, array[787.50, 262.50, 525], 'the same 12.5% off as sold');
  -- 3 days instead: S$180 less 12.5%: S$157.50.
  perform pg_temp.t426_fee('percent off, rate type', rp, 2, 'day', 3, null, array[157.50, 787.50, -630], 'the same 12.5% off as sold');
  -- Then the dates alone: S$157.50 stays.
  perform pg_temp.t426_fee('percent off, dates', rp, 2, 'day', 3, date '2027-09-01', array[157.50, 157.50, 0]);
  -- Rounded to the cent as the invoice rounds it: 33.333% off a day is S$10.00
  -- off S$30 (S$20 sold); off a week, S$50.00 off S$150 (49.9995 rounds up).
  rr := pg_temp.t426_sold(jsonb_build_object('quantity', 1, 'rental_rate_type', 'day', 'rental_periods', 1,
    'line_discount_type', 'percentage', 'line_discount_percent', 33.333, 'line_discount_reason', 'T426 sample'));
  perform pg_temp.t426_fee('percent off, rounding', rr, 1, 'week', 1, null, array[100, 20, 80], 'the same 33.333% off as sold');
  raise notice 'PASS 1b: a change of quantity, rate type or periods keeps the FOC share (1 of 2 free; 2 of 3 to the cent), a free rental stays S$0, the same S$ off (never below S$0) and the same %% off, rounded as the invoice rounds; a change of dates alone keeps the fee as sold (S$95 for S$120 less S$25), difference 0; after a price-only correction to 1 of 2 FOC the fee before is the line''s S$60; the audit row has the old and new fee';
end $$;

-- ===== 2. A description can be cleared =====
do $$
declare sp uuid := pg_temp.t426_id('special'); p uuid := pg_temp.t426_id('product'); v text;
begin
  perform pg_temp.t426_as('manager');
  perform upsert_special_product_from_product(sp, p, 0, 30, 150, 400, 3000, 5, '  Bring the stand back too  ', true);
  if (select description from special_products where id = sp) is distinct from 'Bring the stand back too' then
    raise exception 'FAIL 2: a description given was not saved trimmed'; end if;
  perform upsert_special_product_from_product(sp, p, 0, 30, 150, 400, 3000, 5, null, true);
  if (select description from special_products where id = sp) is distinct from 'Bring the stand back too' then
    raise exception 'FAIL 2: a description left out was not kept'; end if;
  perform upsert_special_product_from_product(sp, p, 0, 30, 150, 400, 3000, 5, '', true);
  if (select description from special_products where id = sp) is not null then
    raise exception 'FAIL 2: an emptied description was not cleared'; end if;
  perform upsert_special_product_from_product(sp, p, 0, 30, 150, 400, 3000, 5, 'Again', true);
  perform upsert_special_product_from_product(sp, p, 0, 30, 150, 400, 3000, 5, '   ', true);
  if (select description from special_products where id = sp) is not null then
    raise exception 'FAIL 2: a description of spaces was not cleared'; end if;
  v := pg_temp.t426_try('staff', format('select public.upsert_special_product_from_product(%L::uuid, %L::uuid, 0, 30, 150, 400, 3000, 5, %L, true)', sp, p, 'Staff text'));
  if v not like '42501 %' then raise exception 'FAIL 2: Staff were not refused with 42501: %', v; end if;
  raise notice 'PASS 2: an emptied description clears it, null keeps it, a given one is trimmed; Staff are refused';
end $$;

-- ===== 3. The old paths are the service role's alone =====
do $$
declare v text; f text; n0 bigint; n1 bigint; r uuid;
begin
  r := pg_temp.t426_rental();
  select count(*) into n0 from special_sales;
  foreach f in array array[
    format('select public.create_special_sale(%L::uuid, %L::uuid, %L::uuid, 1, %L::uuid, null, null)',
      pg_temp.t426_id('special'), pg_temp.t426_id('warehouse'), pg_temp.t426_id('customer'), pg_temp.t426_id('cash')),
    format('select public.create_rental(%L::uuid, %L::uuid, %L::uuid, 1, ''day'', 1, current_date, current_date + 1, null)',
      pg_temp.t426_id('special'), pg_temp.t426_id('warehouse'), pg_temp.t426_id('customer')),
    format('select public.pay_rental(%L::uuid, %L::uuid, null)', r, pg_temp.t426_id('cash')),
    format('select public.activate_rental(%L::uuid)', r),
    format('select public.cancel_rental(%L::uuid, false, null)', r),
    format('select public.cancel_special_sale(%L::uuid, false, null)', gen_random_uuid()),
    format('select public.pay_special_with_credit(''rental'', %L::uuid, %L::uuid, 10, %L::uuid)', r, pg_temp.t426_id('customer'), pg_temp.t426_id('store_a'))]
  loop
    v := pg_temp.t426_try('owner', f);
    if v not like '42501 permission denied for function %' then
      raise exception 'FAIL 3: an Owner could still call it (%): %', v, f; end if;
  end loop;
  foreach f in array array['create_special_sale(uuid,uuid,uuid,integer,uuid,text,text)',
      'create_rental(uuid,uuid,uuid,integer,special_rate_type,integer,date,date,text)', 'pay_rental(uuid,uuid,text)',
      'activate_rental(uuid)', 'cancel_rental(uuid,boolean,text)', 'cancel_special_sale(uuid,boolean,text)',
      'pay_special_with_credit(text,uuid,uuid,numeric,uuid)'] loop
    if has_function_privilege('anon', 'public.' || f, 'execute') or has_function_privilege('authenticated', 'public.' || f, 'execute')
       or not has_function_privilege('service_role', 'public.' || f, 'execute') then
      raise exception 'FAIL 3: public.% is not the service role''s alone', f; end if;
  end loop;
  select count(*) into n1 from special_sales;
  if n1 <> n0 or (select (status::text, credit_funded) from rentals where id = r) is distinct from ('awaiting_fulfilment'::text, 0::numeric(14,2)) then
    raise exception 'FAIL 3: a refused call wrote something'; end if;
  -- Still open to the page: Change, Release, Return, Receive, the waiting list.
  foreach f in array array['update_pending_rental(uuid,integer,special_rate_type,integer,date,date,text)',
      'upsert_special_product_from_product(uuid,uuid,numeric,numeric,numeric,numeric,numeric,numeric,text,boolean)',
      'fulfil_special_doc(text,uuid,uuid,text)', 'special_docs_awaiting_fulfilment()', 'special_product_availability(uuid)',
      'special_stock_in(uuid,uuid,integer,text)', 'receive_returned_rental(uuid,uuid,text,text,uuid)',
      'return_rental_with_fee(uuid,return_condition,boolean,date,boolean,integer,numeric,text,numeric,numeric,text,uuid,text,uuid,text)',
      'products_available_as_special()'] loop
    if not has_function_privilege('authenticated', 'public.' || f, 'execute') then
      raise exception 'FAIL 3: the page can no longer call public.%', f; end if;
  end loop;
  raise notice 'PASS 3: the seven old Special page functions are the service role''s alone (an Owner is refused with 42501, nothing written); the page''s own calls stay open';
end $$;

-- ===== 4. "Receive returned item" on the Rentals tab =====
do $$
declare r uuid; st0 int; x jsonb;
begin
  r := pg_temp.t426_rental();
  perform pg_temp.t426_as('owner');
  perform fulfil_special_doc('rental', r, pg_temp.t426_id('store_b'), 'store');
  perform cancel_invoice_recorded((select invoice_id from rentals where id = r), 'Customer cancelled', gen_random_uuid());
  if not rental_awaiting_return(r) then raise exception 'FAIL 4: the cancelled rental is not waiting to come back'; end if;
  st0 := (select current_qty from store_inventory where store_id = pg_temp.t426_id('store_b') and product_id = pg_temp.t426_id('product'));
  -- The page's call (receiveRpcArgs): good, no warehouse named, its note, a request id.
  if pg_temp.t426_try('manager', format('select public.receive_returned_rental(%L::uuid, null, ''good'', ''Brought back to the counter'', %L::uuid)',
       r, gen_random_uuid())) <> 'ok' then
    raise exception 'FAIL 4: a Manager could not receive it: %', pg_temp.t426_try('manager', format('select public.receive_returned_rental(%L::uuid, null, ''good'', ''x'', null)', r)); end if;
  if (select current_qty from store_inventory where store_id = pg_temp.t426_id('store_b') and product_id = pg_temp.t426_id('product')) <> st0 + 1
     or rental_awaiting_return(r) or not (select stock_returned from rentals where id = r) then
    raise exception 'FAIL 4: it did not go back to the store it came from, once'; end if;
  raise notice 'PASS 4: the Rentals tab''s Receive call puts a rental cancelled while out back where it came from (417)';
end $$;

rollback;
