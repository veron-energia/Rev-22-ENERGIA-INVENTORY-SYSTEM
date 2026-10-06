-- 393: the items still waiting for a warehouse follow their invoice.
--
-- The Owner's rules of 6 Oct 2026: a refund that closes the invoice, a
-- cancellation, or a removed line cancels the invoice's waiting special sales
-- and rentals; a partial refund follows the answer to "Is the customer still
-- taking this item?" (kept with the request through Approvals), and without
-- one cancels an item only when its line's whole value went back; Release and
-- the waiting list refuse an item whose invoice no longer sells it; a reopened
-- invoice paid again brings its item back; released items are never touched
-- or raised twice; a correction that replaces a line on a paid invoice raises
-- the new line's item (only the lines it adds); the migration cancels what was already left waiting on
-- closed invoices and re-runs as a no-op.
--
-- Disposable local database only; everything is rolled back. The migration is
-- applied inside this transaction, so run the file on its own:
--   psql -v ON_ERROR_STOP=1 -f scripts/special/tests/refund-closes-waiting.sql
-- The migration's guards need production's versions of the functions it
-- patches; on a local database that has drifted (correct_invoice, and the
-- staff_may_correct_invoice it calls), install production's bodies right
-- after the begin below, in the same transaction.
-- Every name, phone and amount here is invented.
\set ON_ERROR_STOP on
begin;

create temp table t393(k text primary key, id uuid);

-- A paid invoice of the given lines, as staff raise one.
create function pg_temp.t393_paid(p_items jsonb) returns uuid language plpgsql as $f$
declare v uuid;
begin
  v := public.create_invoice((select id from t393 where k = 'store'), (select id from t393 where k = 'customer'),
         null, p_items);
  perform public.pay_invoice(v, jsonb_build_array(jsonb_build_object(
    'payment_method_id', (select id from t393 where k = 'cash'),
    'amount', public.invoice_charge_total(v) - public.invoice_net_received(v))));
  return v;
end $f$;

-- Records a refund of the given lines from the payment that still holds most.
create function pg_temp.t393_refund(p_inv uuid, p_lines jsonb) returns jsonb language sql as $f$
  select public.refund_invoice_recorded(p_inv, p_lines,
    jsonb_build_array(jsonb_build_object(
      'payment_id', (select id from public.invoice_payments where invoice_id = p_inv
                      order by public.invoice_payment_remaining(id) desc limit 1),
      'amount', (select sum((e->>'amount')::numeric) from jsonb_array_elements(p_lines) e))),
    '[]', 'Fixture refund', gen_random_uuid())
$f$;

-- An invoice line, machines before rentals (invoice lines carry no order of
-- their own; two machines are told apart by id, consistently).
create function pg_temp.t393_line(p_inv uuid, p_n int) returns uuid language sql as $f$
  select id from public.invoice_items where invoice_id = p_inv
   order by line_kind::text desc, id offset p_n - 1 limit 1
$f$;

-- The newest waiting item raised for a line, special sale or rental.
create function pg_temp.t393_doc(p_line uuid) returns uuid language sql as $f$
  select id from (select id, created_at, sale_no no from public.special_sales where invoice_item_id = p_line
                  union all
                  select id, created_at, rental_no from public.rentals where invoice_item_id = p_line) d
   order by created_at desc, no desc limit 1
$f$;

create function pg_temp.t393_status(p_doc uuid) returns text language sql as $f$
  select coalesce((select status from public.special_sales where id = p_doc),
                  (select status::text from public.rentals where id = p_doc))
$f$;

create function pg_temp.t393_notes(p_doc uuid) returns text language sql as $f$
  select coalesce((select notes from public.special_sales where id = p_doc),
                  (select notes from public.rentals where id = p_doc), '')
$f$;

create function pg_temp.t393_listed(p_doc uuid) returns boolean language sql as $f$
  select exists (select 1 from public.special_docs_awaiting_fulfilment() w where w.doc_id = p_doc)
$f$;

-- Puts an item back to waiting, as items were left before 393.
create function pg_temp.t393_unclose(p_doc uuid) returns void language sql as $f$
  update public.special_sales set status = 'pending', cancelled_at = null,
         notes = 'From invoice (fixture)' where id = p_doc;
  update public.rentals set status = 'awaiting_fulfilment', cancelled_at = null,
         notes = 'From invoice (fixture)' where id = p_doc;
$f$;

-- ===== Fixtures, and items left waiting on closed invoices (the state 393 finds) =====
do $$
declare o uuid := gen_random_uuid(); st uuid; wh uuid; c uuid; pm uuid; p uuid; sp uuid;
  inv uuid; d uuid;
begin
  insert into auth.users(id, email) values (o, 'owner393@sig.invalid');
  insert into public.profiles(id, full_name, email, role, is_active)
    values (o, 'Fixture Owner', 'owner393@sig.invalid', 'owner', true);
  perform set_config('request.jwt.claims', json_build_object('sub', o::text)::text, true);
  perform set_config('request.jwt.claim.sub', o::text, true);
  insert into public.stores(name, code, country_code) values ('Fixture Store 393', 'T393', 'SG') returning id into st;
  insert into public.warehouses(name, code) values ('Fixture Warehouse 393', 'T393W') returning id into wh;
  insert into public.payment_methods(name, is_active) values ('Fixture Cash 393', true) returning id into pm;
  insert into public.customers(full_name, phone) values ('Jane Tan', '+6591392001') returning id into c;
  insert into public.products(name, sku, product_type) values ('Fixture Machine 393', 'T393-M', 'own') returning id into p;
  insert into public.warehouse_inventory(warehouse_id, product_id, current_qty) values (wh, p, 20);
  sp := public.upsert_special_product_from_product(null, p, 300, 30, null, null, null, 10);
  insert into t393 values ('owner', o), ('store', st), ('warehouse', wh), ('cash', pm), ('customer', c),
    ('product', p), ('special', sp);

  -- Refunded: a machine and a two-day rental, both left waiting.
  inv := pg_temp.t393_paid(jsonb_build_array(
    jsonb_build_object('kind', 'special_product', 'special_product_id', sp, 'quantity', 1),
    jsonb_build_object('kind', 'rental', 'special_product_id', sp, 'quantity', 1,
      'rental_rate_type', 'day', 'rental_periods', 2)));
  if (select total_amount from public.invoices where id = inv) <> 360 then
    raise exception 'FIXTURE: the machine and rental did not price to 300 + 2 x 30'; end if;
  perform pg_temp.t393_refund(inv, jsonb_build_array(
    jsonb_build_object('invoice_item_id', pg_temp.t393_line(inv, 1), 'amount', 300),
    jsonb_build_object('invoice_item_id', pg_temp.t393_line(inv, 2), 'amount', 60)));
  if (select status::text from public.invoices where id = inv) <> 'refunded' then
    raise exception 'FIXTURE: the full refund did not close the invoice'; end if;
  perform pg_temp.t393_unclose(pg_temp.t393_doc(pg_temp.t393_line(inv, 1)));
  perform pg_temp.t393_unclose(pg_temp.t393_doc(pg_temp.t393_line(inv, 2)));
  insert into t393 values ('bf_refunded_sale', pg_temp.t393_doc(pg_temp.t393_line(inv, 1))),
    ('bf_refunded_rental', pg_temp.t393_doc(pg_temp.t393_line(inv, 2)));

  -- Cancelled with the money kept: its machine left waiting.
  inv := pg_temp.t393_paid(jsonb_build_array(
    jsonb_build_object('kind', 'special_product', 'special_product_id', sp, 'quantity', 1)));
  perform public.cancel_invoice_recorded(inv, 'Fixture cancellation', gen_random_uuid());
  perform pg_temp.t393_unclose(pg_temp.t393_doc(pg_temp.t393_line(inv, 1)));
  insert into t393 values ('bf_cancelled_sale', pg_temp.t393_doc(pg_temp.t393_line(inv, 1)));

  -- Deleted (as no paid invoice can be through the app, but the rule names it).
  inv := pg_temp.t393_paid(jsonb_build_array(
    jsonb_build_object('kind', 'special_product', 'special_product_id', sp, 'quantity', 1)));
  update public.invoices set deleted_at = now() where id = inv;
  insert into t393 values ('bf_deleted_sale', pg_temp.t393_doc(pg_temp.t393_line(inv, 1)));

  -- Open and paid: its machine keeps waiting.
  inv := pg_temp.t393_paid(jsonb_build_array(
    jsonb_build_object('kind', 'special_product', 'special_product_id', sp, 'quantity', 1)));
  insert into t393 values ('bf_open_sale', pg_temp.t393_doc(pg_temp.t393_line(inv, 1)));

  -- Released, then refunded: the released machine is not the migration's.
  inv := pg_temp.t393_paid(jsonb_build_array(
    jsonb_build_object('kind', 'special_product', 'special_product_id', sp, 'quantity', 1)));
  d := pg_temp.t393_doc(pg_temp.t393_line(inv, 1));
  perform public.fulfil_special_doc('special_sale', d, wh, 'warehouse');
  perform pg_temp.t393_refund(inv, jsonb_build_array(
    jsonb_build_object('invoice_item_id', pg_temp.t393_line(inv, 1), 'amount', 300)));
  insert into t393 values ('bf_released_sale', d);

  if pg_temp.t393_status((select id from t393 where k = 'bf_released_sale')) <> 'completed' then
    raise exception 'FIXTURE: the released machine is not completed'; end if;
  if exists (select 1 from t393 where k like 'bf_%' and k <> 'bf_released_sale'
               and pg_temp.t393_status(id) not in ('pending', 'awaiting_fulfilment')) then
    raise exception 'FIXTURE: an item meant to be waiting is not'; end if;
end $$;

-- What the migration should find: every item still waiting on a closed invoice.
create temp table t393_stale as
  select s.id from public.special_sales s join public.invoices i on i.id = s.invoice_id
   where s.status = 'pending' and s.warehouse_id is null and s.source_store_id is null
     and (i.deleted_at is not null or i.status in ('refunded', 'cancelled'))
  union all
  select x.id from public.rentals x join public.invoices i on i.id = x.invoice_id
   where x.status = 'awaiting_fulfilment' and x.warehouse_id is null and x.source_store_id is null
     and (i.deleted_at is not null or i.status in ('refunded', 'cancelled'));
create temp table t393_before as
  select id, status, cancelled_at, notes from public.special_sales
  union all select id, status::text, cancelled_at, notes from public.rentals;

\ir ../../../supabase/393_refunds_close_waiting_special_items.sql

-- ===== 1. The migration cancels exactly what was left waiting on closed invoices =====
do $$
declare n int;
begin
  if (select count(*) from t393_stale where id in (select id from t393 where k like 'bf_%')) <> 4 then
    raise exception 'FAIL 1: the four fixture items left waiting were not all found stale'; end if;
  select count(*) into n from t393_stale st
   where pg_temp.t393_status(st.id) = 'cancelled'
     and pg_temp.t393_notes(st.id) like '%the invoice was already closed when 393 was applied%'
     and coalesce((select cancelled_at from public.special_sales where id = st.id),
                  (select cancelled_at from public.rentals where id = st.id)) is not null;
  if n <> (select count(*) from t393_stale) then
    raise exception 'FAIL 1: % of % stale items were cancelled', n, (select count(*) from t393_stale); end if;
  if pg_temp.t393_notes((select id from t393 where k = 'bf_refunded_sale')) not like '%Cancelled (refunded): %'
     or pg_temp.t393_notes((select id from t393 where k = 'bf_refunded_rental')) not like '%Cancelled (refunded): %'
     or pg_temp.t393_notes((select id from t393 where k = 'bf_cancelled_sale')) not like '%Cancelled (invoice cancelled): %'
     or pg_temp.t393_notes((select id from t393 where k = 'bf_deleted_sale')) not like '%Cancelled (invoice deleted): %' then
    raise exception 'FAIL 1: a cancelled item does not say why'; end if;
  -- Nothing else moved: not the open invoice's machine, not the released one,
  -- not any other row in the database.
  select count(*) into n from t393_before b
    join (select id, status, cancelled_at, notes from public.special_sales
          union all select id, status::text, cancelled_at, notes from public.rentals) a on a.id = b.id
   where b.id not in (select id from t393_stale)
     and (a.status, a.cancelled_at, a.notes) is distinct from (b.status, b.cancelled_at, b.notes);
  if n <> 0 then raise exception 'FAIL 1: the migration changed % other special sale or rental row(s)', n; end if;
  if pg_temp.t393_status((select id from t393 where k = 'bf_open_sale')) <> 'pending'
     or pg_temp.t393_status((select id from t393 where k = 'bf_released_sale')) <> 'completed' then
    raise exception 'FAIL 1: an open or released item was touched'; end if;
  if (select count(*) from public.audit_logs where action = 'waiting_item_cancelled'
        and record_id in (select id from t393_stale)) <> (select count(*) from t393_stale) then
    raise exception 'FAIL 1: not every cancellation was audited'; end if;
  raise notice 'PASS 1: the migration cancelled the % item(s) left waiting on refunded, cancelled and deleted invoices, each saying why and audited, and nothing else', (select count(*) from t393_stale);
end $$;

-- ===== 2. A second run changes nothing =====
create temp table t393_fns as
  select p.oid::regprocedure::text fn, md5(pg_get_functiondef(p.oid)) h, p.proacl::text acl
    from pg_proc p where p.pronamespace = 'public'::regnamespace;
create temp table t393_rows as
  select id, status, cancelled_at, notes from public.special_sales
  union all select id, status::text, cancelled_at, notes from public.rentals;
create temp table t393_audits as select count(*) n from public.audit_logs;

\ir ../../../supabase/393_refunds_close_waiting_special_items.sql

do $$
begin
  if exists (select fn, h, acl from t393_fns
             except select p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid)), p.proacl::text
                      from pg_proc p where p.pronamespace = 'public'::regnamespace)
     or (select count(*) from t393_fns) <> (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace) then
    raise exception 'FAIL 2: re-running 393 changed a function or its grants'; end if;
  if exists (select * from t393_rows
             except (select id, status, cancelled_at, notes from public.special_sales
                     union all select id, status::text, cancelled_at, notes from public.rentals)) then
    raise exception 'FAIL 2: re-running 393 changed a special sale or rental'; end if;
  if (select count(*) from public.audit_logs) <> (select n from t393_audits) then
    raise exception 'FAIL 2: re-running 393 wrote audit rows'; end if;
  if (select count(*) from pg_trigger where tgrelid = 'public.invoice_items'::regclass
        and tgname = 'special_docs_follow_line_removed') <> 1 then
    raise exception 'FAIL 2: the line-removed trigger is not there exactly once'; end if;
  raise notice 'PASS 2: a second run of 393 changes no function, grant, row or audit';
end $$;

-- ===== 3. Behaviour =====
do $$
declare sp uuid := (select id from t393 where k = 'special'); wh uuid := (select id from t393 where k = 'warehouse');
  inv uuid; x uuid; y uuid; dx uuid; dy uuid; d uuid; req jsonb; res jsonb; n int; msg text;
  machine jsonb; rental jsonb;
begin
  machine := jsonb_build_object('kind', 'special_product', 'special_product_id', sp, 'quantity', 1);
  rental := jsonb_build_object('kind', 'rental', 'special_product_id', sp, 'quantity', 1,
    'rental_rate_type', 'day', 'rental_periods', 2);

  -- 3a. A full refund cancels every waiting item, unasked.
  inv := pg_temp.t393_paid(jsonb_build_array(machine, rental));
  x := pg_temp.t393_line(inv, 1); y := pg_temp.t393_line(inv, 2);
  dx := pg_temp.t393_doc(x); dy := pg_temp.t393_doc(y);
  if not pg_temp.t393_listed(dx) or not pg_temp.t393_listed(dy) then
    raise exception 'FAIL 3a: paying did not put the machine and rental on the waiting list'; end if;
  perform pg_temp.t393_refund(inv, jsonb_build_array(
    jsonb_build_object('invoice_item_id', x, 'amount', 300,
      'waiting', jsonb_build_array(jsonb_build_object('doc_id', dx, 'still_taking', true))),
    jsonb_build_object('invoice_item_id', y, 'amount', 60)));
  if (select status::text from public.invoices where id = inv) <> 'refunded'
     or pg_temp.t393_status(dx) <> 'cancelled' or pg_temp.t393_status(dy) <> 'cancelled' then
    raise exception 'FAIL 3a: a full refund left a waiting item (sale %, rental %)',
      pg_temp.t393_status(dx), pg_temp.t393_status(dy); end if;
  if pg_temp.t393_notes(dx) not like '%Cancelled (refunded): Fixture refund%'
     or (select cancelled_at from public.special_sales where id = dx) is null
     or (select cancelled_at from public.rentals where id = dy) is null then
    raise exception 'FAIL 3a: the cancellation has no time or does not say it was refunded'; end if;
  if (select count(*) from public.audit_logs where action = 'waiting_item_cancelled' and record_id in (dx, dy)) <> 2 then
    raise exception 'FAIL 3a: the cancellations were not audited'; end if;
  if pg_temp.t393_listed(dx) or pg_temp.t393_listed(dy) then
    raise exception 'FAIL 3a: a refunded item is still on the waiting list'; end if;
  insert into t393 values ('refunded_inv', inv), ('refunded_sale', dx);
  raise notice 'PASS 3a: a refund that closes the invoice cancels its waiting machine and rental, even one answered "still taking", with the time, the reason and an audit row, and they leave the waiting list';

  -- 3b. A partial refund follows the answers: Yes keeps, No cancels.
  inv := pg_temp.t393_paid(jsonb_build_array(machine, machine));
  x := pg_temp.t393_line(inv, 1); y := pg_temp.t393_line(inv, 2);
  dx := pg_temp.t393_doc(x); dy := pg_temp.t393_doc(y);
  -- Answers that do not hold are refused, and the refund with them.
  foreach msg in array array['not on this invoice', 'yes or no', 'once'] loop
    begin
      perform pg_temp.t393_refund(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', x, 'amount', 300,
        'waiting', case msg
          when 'not on this invoice' then jsonb_build_array(jsonb_build_object('doc_id', gen_random_uuid(), 'still_taking', false))
          when 'yes or no' then jsonb_build_array(jsonb_build_object('doc_id', dx, 'still_taking', 'no'))
          else jsonb_build_array(jsonb_build_object('doc_id', dx, 'still_taking', true),
                                 jsonb_build_object('doc_id', dx, 'still_taking', false)) end)));
      raise exception 'FAIL 3b: an answer % was accepted', msg;
    exception when raise_exception then
      if sqlerrm like 'FAIL%' or sqlerrm not like '%' || msg || '%' then raise; end if;
    end;
  end loop;
  if exists (select 1 from public.invoice_refunds where invoice_id = inv) then
    raise exception 'FAIL 3b: a refusal left a refund behind'; end if;
  -- Line X refunded in full but the customer still takes its machine; line Y
  -- not refunded but its machine is not wanted.
  perform pg_temp.t393_refund(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', x, 'amount', 300,
    'waiting', jsonb_build_array(jsonb_build_object('doc_id', dx, 'still_taking', true),
                                 jsonb_build_object('doc_id', upper(dy::text), 'still_taking', false)))));
  if (select status::text from public.invoices where id = inv) = 'refunded' then
    raise exception 'FIXTURE 3b: half the invoice closed it'; end if;
  if pg_temp.t393_status(dx) <> 'pending' or not pg_temp.t393_listed(dx) then
    raise exception 'FAIL 3b: "still taking" did not keep the machine waiting'; end if;
  if pg_temp.t393_status(dy) <> 'cancelled' or pg_temp.t393_listed(dy) then
    raise exception 'FAIL 3b: "not taking" did not cancel the machine'; end if;
  insert into t393 values ('open_sale', dx);
  raise notice 'PASS 3b: a partial refund keeps the machine the customer still takes and cancels the one they do not, whichever line the money came from; answers naming another invoice''s item, not yes or no, or twice are refused with the refund';

  -- 3c. Without an answer: cancelled only when its line went back in full (to the cent).
  inv := pg_temp.t393_paid(jsonb_build_array(machine, machine));
  x := pg_temp.t393_line(inv, 1); y := pg_temp.t393_line(inv, 2);
  dx := pg_temp.t393_doc(x); dy := pg_temp.t393_doc(y);
  perform pg_temp.t393_refund(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', x, 'amount', 300)));
  if pg_temp.t393_status(dx) <> 'cancelled' then
    raise exception 'FAIL 3c: a line refunded in full left its machine waiting'; end if;
  if pg_temp.t393_status(dy) <> 'pending' then
    raise exception 'FAIL 3c: a line not refunded lost its machine'; end if;
  perform pg_temp.t393_refund(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', y, 'amount', 100)));
  if pg_temp.t393_status(dy) <> 'pending' then
    raise exception 'FAIL 3c: a third of the line back cancelled its machine'; end if;
  perform pg_temp.t393_refund(inv, jsonb_build_array(jsonb_build_object('invoice_item_id', y, 'amount', 199.99)));
  if (select status::text from public.invoices where id = inv) = 'refunded' then
    raise exception 'FIXTURE 3c: a cent short closed the invoice'; end if;
  if pg_temp.t393_status(dy) <> 'cancelled' then
    raise exception 'FAIL 3c: the line back to within a cent left its machine waiting'; end if;
  raise notice 'PASS 3c: with no answer a machine is cancelled only when its line has gone back in full, to within a cent, and a line the refund does not touch keeps its machine';

  -- 3d. Through Approvals: the requester''s answers are kept and honoured.
  inv := pg_temp.t393_paid(jsonb_build_array(machine, machine));
  x := pg_temp.t393_line(inv, 1); y := pg_temp.t393_line(inv, 2);
  dx := pg_temp.t393_doc(x); dy := pg_temp.t393_doc(y);
  req := public.request_invoice_action_v2(inv, 'refund_partial', jsonb_build_array(
    jsonb_build_object('invoice_item_id', x, 'quantity', 1,
      'waiting', jsonb_build_array(jsonb_build_object('doc_id', dx, 'still_taking', true),
                                   jsonb_build_object('doc_id', dy, 'still_taking', false)))),
    'Customer returns one machine', null, gen_random_uuid());
  if pg_temp.t393_status(dx) <> 'pending' or pg_temp.t393_status(dy) <> 'pending' then
    raise exception 'FAIL 3d: raising the request changed an item before approval'; end if;
  if (select jsonb_array_length(r.payload->'lines'->0->'waiting') from public.approval_requests r
       where r.id = (req->>'request_id')::uuid) <> 2 then
    raise exception 'FAIL 3d: the request did not keep the answers'; end if;
  res := public.resolve_invoice_action_v2((req->>'request_id')::uuid, true, 'Approved', null, '[]'::jsonb, null, false);
  if res->>'status' <> 'approved' or not coalesce((res->>'refund_recorded')::boolean, false) then
    raise exception 'FAIL 3d: the approval did not record the refund: %', res; end if;
  if pg_temp.t393_status(dx) <> 'pending' or pg_temp.t393_status(dy) <> 'cancelled' then
    raise exception 'FAIL 3d: the approved refund ignored the answers (refunded line %, other line %)',
      pg_temp.t393_status(dx), pg_temp.t393_status(dy); end if;
  -- A request with no answers (raised before the question existed) falls back.
  inv := pg_temp.t393_paid(jsonb_build_array(machine, machine));
  x := pg_temp.t393_line(inv, 1); y := pg_temp.t393_line(inv, 2);
  dx := pg_temp.t393_doc(x); dy := pg_temp.t393_doc(y);
  req := public.request_invoice_action_v2(inv, 'refund_partial',
    jsonb_build_array(jsonb_build_object('invoice_item_id', x, 'quantity', 1)),
    'Customer returns one machine', null, gen_random_uuid());
  res := public.resolve_invoice_action_v2((req->>'request_id')::uuid, true, 'Approved', null, '[]'::jsonb, null, false);
  if pg_temp.t393_status(dx) <> 'cancelled' or pg_temp.t393_status(dy) <> 'pending' then
    raise exception 'FAIL 3d: an approved refund with no answers did not fall back (refunded line %, other line %)',
      pg_temp.t393_status(dx), pg_temp.t393_status(dy); end if;
  raise notice 'PASS 3d: through Approvals the answers stay with the request, nothing moves until approval, and the approved refund honours them; a request without answers falls back to the whole-line rule';

  -- 3e. Cancelling the invoice cancels its waiting machine as well as its rental.
  inv := pg_temp.t393_paid(jsonb_build_array(machine, rental));
  dx := pg_temp.t393_doc(pg_temp.t393_line(inv, 1)); dy := pg_temp.t393_doc(pg_temp.t393_line(inv, 2));
  perform public.cancel_invoice_recorded(inv, 'Customer changed their mind', gen_random_uuid());
  if pg_temp.t393_status(dx) <> 'cancelled'
     or pg_temp.t393_notes(dx) not like '%Cancelled (invoice cancelled): Customer changed their mind%' then
    raise exception 'FAIL 3e: cancelling the invoice left its machine waiting'; end if;
  if pg_temp.t393_status(dy) <> 'cancelled' then
    raise exception 'FAIL 3e: cancelling the invoice left its rental waiting'; end if;
  if pg_temp.t393_listed(dx) or pg_temp.t393_listed(dy) then
    raise exception 'FAIL 3e: a cancelled invoice''s item is still on the waiting list'; end if;
  insert into t393 values ('cancelled_inv', inv), ('cancelled_sale', dx);
  raise notice 'PASS 3e: cancelling an invoice cancels its waiting machine, saying so, beside its rental';

  -- 3f. A line removed from the invoice cancels its waiting item only.
  inv := pg_temp.t393_paid(jsonb_build_array(machine, machine));
  x := pg_temp.t393_line(inv, 1); y := pg_temp.t393_line(inv, 2);
  dx := pg_temp.t393_doc(x); dy := pg_temp.t393_doc(y);
  delete from public.invoice_items where id = y;   -- as update_invoice_internal removes a line
  if pg_temp.t393_status(dy) <> 'cancelled' or pg_temp.t393_notes(dy) not like '%Cancelled (line removed)%' then
    raise exception 'FAIL 3f: removing the line left its machine waiting'; end if;
  if pg_temp.t393_status(dx) <> 'pending' then
    raise exception 'FAIL 3f: removing one line cancelled the other line''s machine'; end if;
  insert into t393 values ('removed_line_sale', dy);
  raise notice 'PASS 3f: removing a line cancels its waiting machine and leaves the other line''s';

  -- 3g. Release and the waiting list refuse an item its invoice no longer sells.
  for d, msg in select id, m from (values
      ((select id from t393 where k = 'refunded_sale'), 'was refunded'),
      ((select id from t393 where k = 'cancelled_sale'), 'was cancelled'),
      ((select id from t393 where k = 'removed_line_sale'), 'its line was removed'),
      ((select id from t393 where k = 'bf_deleted_sale'), 'was deleted')) v(id, m)
  loop
    perform pg_temp.t393_unclose(d);   -- left waiting, as before 393
    if pg_temp.t393_listed(d) then
      raise exception 'FAIL 3g: an item whose invoice % is on the waiting list', msg; end if;
    begin
      perform public.fulfil_special_doc('special_sale', d, wh, 'warehouse');
      raise exception 'FAIL 3g: released an item whose invoice %', msg;
    exception when raise_exception then
      if sqlerrm like 'FAIL%' or sqlerrm not like '%cannot be released: %' || msg || '%' then raise; end if;
    end;
    if pg_temp.t393_status(d) <> 'pending'
       or (select current_qty from public.warehouse_inventory
            where warehouse_id = wh and product_id = (select id from t393 where k = 'product')) <> 19 then
      raise exception 'FAIL 3g: a refused release moved stock or the item'; end if;
  end loop;
  -- An item on an open invoice still releases.
  d := (select id from t393 where k = 'open_sale');
  perform public.fulfil_special_doc('special_sale', d, wh, 'warehouse');
  if pg_temp.t393_status(d) <> 'completed' then
    raise exception 'FAIL 3g: an open invoice''s machine could not be released'; end if;
  raise notice 'PASS 3g: Release refuses, and the waiting list leaves out, an item whose invoice was refunded, cancelled or deleted or whose line was removed, saying which, and moves no stock; an open invoice''s item still releases';

  -- 3h. A refunded invoice reopened and paid again brings its items back, once.
  inv := pg_temp.t393_paid(jsonb_build_array(machine, rental));
  x := pg_temp.t393_line(inv, 1); y := pg_temp.t393_line(inv, 2);
  dx := pg_temp.t393_doc(x); dy := pg_temp.t393_doc(y);
  perform pg_temp.t393_refund(inv, jsonb_build_array(
    jsonb_build_object('invoice_item_id', x, 'amount', 300), jsonb_build_object('invoice_item_id', y, 'amount', 60)));
  perform public.reopen_invoice(inv, 'Customer came back for it', gen_random_uuid());
  if (select status::text from public.invoices where id = inv) <> 'unpaid' then
    raise exception 'FIXTURE 3h: the reopened invoice is %', (select status from public.invoices where id = inv); end if;
  if pg_temp.t393_doc(x) <> dx or pg_temp.t393_doc(y) <> dy then
    raise exception 'FAIL 3h: reopening an unpaid invoice raised its items before payment'; end if;
  perform public.pay_invoice(inv, jsonb_build_array(jsonb_build_object(
    'payment_method_id', (select id from t393 where k = 'cash'), 'amount', 360)));
  if pg_temp.t393_doc(x) = dx or pg_temp.t393_status(pg_temp.t393_doc(x)) <> 'pending'
     or not pg_temp.t393_listed(pg_temp.t393_doc(x)) then
    raise exception 'FAIL 3h: paying the reopened invoice did not bring its machine back'; end if;
  if pg_temp.t393_doc(y) = dy or pg_temp.t393_status(pg_temp.t393_doc(y)) <> 'awaiting_fulfilment' then
    raise exception 'FAIL 3h: paying the reopened invoice did not bring its rental back'; end if;
  if pg_temp.t393_status(dx) <> 'cancelled' then
    raise exception 'FAIL 3h: the first, cancelled machine changed'; end if;
  if public.create_special_docs_for_invoice(inv) <> 0 then
    raise exception 'FAIL 3h: raising the items again made a second copy'; end if;
  -- Cancelled with the money kept, then reopened: paid at once, items back.
  inv := pg_temp.t393_paid(jsonb_build_array(machine));
  x := pg_temp.t393_line(inv, 1); dx := pg_temp.t393_doc(x);
  perform public.cancel_invoice_recorded(inv, 'Cancelled in error', gen_random_uuid());
  perform public.reopen_invoice(inv, 'Cancelled in error', gen_random_uuid());
  if (select status::text from public.invoices where id = inv) <> 'paid' then
    raise exception 'FIXTURE 3h: the reopened invoice is %', (select status from public.invoices where id = inv); end if;
  if pg_temp.t393_doc(x) = dx or pg_temp.t393_status(pg_temp.t393_doc(x)) <> 'pending' then
    raise exception 'FAIL 3h: reopening a cancelled, paid invoice did not bring its machine back'; end if;
  raise notice 'PASS 3h: a refunded invoice reopened and paid again raises its machine and rental afresh, once; one reopened straight to paid raises them on reopening';

  -- 3i. Released items are never touched.
  inv := pg_temp.t393_paid(jsonb_build_array(machine, machine));
  x := pg_temp.t393_line(inv, 1); y := pg_temp.t393_line(inv, 2);
  dx := pg_temp.t393_doc(x); dy := pg_temp.t393_doc(y);
  perform public.fulfil_special_doc('special_sale', dx, wh, 'warehouse');
  perform pg_temp.t393_refund(inv, jsonb_build_array(
    jsonb_build_object('invoice_item_id', x, 'amount', 300,
      'waiting', jsonb_build_array(jsonb_build_object('doc_id', dx, 'still_taking', false))),
    jsonb_build_object('invoice_item_id', y, 'amount', 300)));
  if pg_temp.t393_status(dx) <> 'completed' then
    raise exception 'FAIL 3i: a refund touched a released machine'; end if;
  if pg_temp.t393_status(dy) <> 'cancelled' then
    raise exception 'FAIL 3i: the waiting machine beside it was left'; end if;
  inv := pg_temp.t393_paid(jsonb_build_array(machine));
  dx := pg_temp.t393_doc(pg_temp.t393_line(inv, 1));
  perform public.fulfil_special_doc('special_sale', dx, wh, 'warehouse');
  perform public.cancel_invoice_recorded(inv, 'Cancelled after release', gen_random_uuid());
  if pg_temp.t393_status(dx) <> 'completed' then
    raise exception 'FAIL 3i: a cancellation touched a released machine'; end if;
  if public.special_doc_invoice_problem(null, null) is not null then
    raise exception 'FAIL 3i: an item with no invoice has a problem'; end if;
  raise notice 'PASS 3i: released machines stay released through a refund (even answered "not taking") and a cancellation';

  -- 3j. A rental released, then cancelled with its invoice while still out,
  -- is the line's for good: reopening the invoice straight to paid raises no
  -- second rental for a machine the customer already has.
  inv := pg_temp.t393_paid(jsonb_build_array(rental));
  y := pg_temp.t393_line(inv, 1); dy := pg_temp.t393_doc(y);
  perform public.fulfil_special_doc('rental', dy, wh, 'warehouse');
  if pg_temp.t393_status(dy) <> 'active' then
    raise exception 'FIXTURE 3j: the released rental is %', pg_temp.t393_status(dy); end if;
  perform public.cancel_invoice_recorded(inv, 'Cancelled while the rental is out', gen_random_uuid());
  if pg_temp.t393_status(dy) <> 'cancelled' then
    raise exception 'FIXTURE 3j: the rental out was not cancelled with its invoice'; end if;
  perform public.reopen_invoice(inv, 'Cancelled in error', gen_random_uuid());
  if (select status::text from public.invoices where id = inv) <> 'paid' then
    raise exception 'FIXTURE 3j: the reopened invoice is %', (select status from public.invoices where id = inv); end if;
  if (select count(*) from public.rentals where invoice_item_id = y) <> 1
     or exists (select 1 from public.special_docs_awaiting_fulfilment() w
                  join public.rentals r on r.id = w.doc_id where r.invoice_id = inv) then
    raise exception 'FAIL 3j: reopening raised a second rental for a machine still out (% rentals on the line)',
      (select count(*) from public.rentals where invoice_item_id = y); end if;
  if public.create_special_docs_for_invoice(inv) <> 0 then
    raise exception 'FAIL 3j: raising the items again made a second rental'; end if;
  raise notice 'PASS 3j: a rental released and cancelled with its invoice is not raised again when the invoice is reopened and paid';

  -- 3k. A correction that replaces a line on a paid invoice (a machine
  -- changed to a rental: the old line goes, a new one comes) cancels the old
  -- waiting item and raises the new line's, as paying would; one that leaves
  -- a balance raises it when the balance is paid; one that changes no line
  -- raises nothing.
  inv := pg_temp.t393_paid(jsonb_build_array(machine, machine));
  x := pg_temp.t393_line(inv, 1); y := pg_temp.t393_line(inv, 2);
  dx := pg_temp.t393_doc(x); dy := pg_temp.t393_doc(y);
  perform public.correct_invoice(inv, jsonb_build_array(
      jsonb_build_object('invoice_item_id', x, 'kind', 'special_product', 'special_product_id', sp, 'quantity', 1),
      rental),
    '{}'::jsonb, 'The second machine is rented, not sold', gen_random_uuid());
  if (select status::text from public.invoices where id = inv) <> 'paid' then
    raise exception 'FIXTURE 3k: the corrected invoice is %', (select status from public.invoices where id = inv); end if;
  if exists (select 1 from public.invoice_items where id = y) then
    raise exception 'FIXTURE 3k: the replaced line is still there'; end if;
  if pg_temp.t393_status(dy) <> 'cancelled' or pg_temp.t393_notes(dy) not like '%Cancelled (line removed)%' then
    raise exception 'FAIL 3k: the replaced line''s machine was left waiting'; end if;
  if (select count(*) from public.rentals r join public.invoice_items ii on ii.id = r.invoice_item_id
       where ii.invoice_id = inv and ii.line_kind::text = 'rental' and r.status = 'awaiting_fulfilment') <> 1
     or not exists (select 1 from public.special_docs_awaiting_fulfilment() w
                     join public.rentals r on r.id = w.doc_id where r.invoice_id = inv) then
    raise exception 'FAIL 3k: the new rental line has nothing waiting for a warehouse'; end if;
  if pg_temp.t393_doc(x) <> dx or pg_temp.t393_status(dx) <> 'pending'
     or (select count(*) from public.special_sales where invoice_item_id = x) <> 1 then
    raise exception 'FAIL 3k: the kept line''s machine changed or was raised twice'; end if;
  -- Replaced by a dearer rental: a balance is due, so nothing waits until it is paid.
  inv := pg_temp.t393_paid(jsonb_build_array(machine));
  x := pg_temp.t393_line(inv, 1); dx := pg_temp.t393_doc(x);
  perform public.correct_invoice(inv, jsonb_build_array(rental || '{"rental_periods": 20}'::jsonb),
    '{}'::jsonb, 'Rented for twenty days instead', gen_random_uuid());
  if (select status::text from public.invoices where id = inv) <> 'partially_paid' then
    raise exception 'FIXTURE 3k: the dearer correction left the invoice %', (select status from public.invoices where id = inv); end if;
  if pg_temp.t393_status(dx) <> 'cancelled'
     or exists (select 1 from public.rentals where invoice_id = inv) then
    raise exception 'FAIL 3k: a correction leaving a balance raised the rental before payment'; end if;
  perform public.pay_invoice(inv, jsonb_build_array(jsonb_build_object(
    'payment_method_id', (select id from t393 where k = 'cash'),
    'amount', public.invoice_charge_total(inv) - public.invoice_net_received(inv))));
  if (select count(*) from public.rentals where invoice_id = inv and status = 'awaiting_fulfilment') <> 1 then
    raise exception 'FAIL 3k: paying the balance did not raise the new rental'; end if;
  -- A correction that changes no line raises nothing, even for a paid line
  -- that has no item (as one left from before items existed would).
  inv := pg_temp.t393_paid(jsonb_build_array(machine));
  x := pg_temp.t393_line(inv, 1);
  delete from public.special_sales where invoice_item_id = x;
  perform public.correct_invoice(inv, jsonb_build_array(
      jsonb_build_object('invoice_item_id', x, 'kind', 'special_product', 'special_product_id', sp, 'quantity', 1)),
    jsonb_build_object('notes', 'Fixture note'), 'Note added', gen_random_uuid());
  if exists (select 1 from public.special_sales where invoice_item_id = x) then
    raise exception 'FAIL 3k: a correction that changed no line raised an item'; end if;
  raise notice 'PASS 3k: a correction replacing a line on a paid invoice cancels the old waiting machine and raises the new line''s rental; with a balance left it waits for the payment; a correction changing no line raises nothing';

  -- 3l. On an invoice that was already paid, a correction raises only the
  -- lines it adds; a line already there without an item (as one from before
  -- invoices raised items would be) is left without one (the Owner, 6 Oct 2026).
  inv := pg_temp.t393_paid(jsonb_build_array(machine, machine));
  x := pg_temp.t393_line(inv, 1); y := pg_temp.t393_line(inv, 2);
  delete from public.special_sales where invoice_item_id = x;
  perform public.correct_invoice(inv, jsonb_build_array(
      jsonb_build_object('invoice_item_id', x, 'kind', 'special_product', 'special_product_id', sp, 'quantity', 1),
      rental),
    '{}'::jsonb, 'The second machine is rented, not sold', gen_random_uuid());
  if (select status::text from public.invoices where id = inv) <> 'paid' then
    raise exception 'FIXTURE 3l: the corrected invoice is %', (select status from public.invoices where id = inv); end if;
  if exists (select 1 from public.special_sales where invoice_item_id = x) then
    raise exception 'FAIL 3l: a line already on the paid invoice without an item was raised by the correction'; end if;
  if (select count(*) from public.rentals where invoice_id = inv and status = 'awaiting_fulfilment') <> 1 then
    raise exception 'FAIL 3l: the line the correction added has nothing waiting for a warehouse'; end if;
  if coalesce(current_setting('energia.special_docs_only', true), '') <> '' then
    raise exception 'FAIL 3l: the correction left its list of added lines set for the rest of the transaction'; end if;
  raise notice 'PASS 3l: on an invoice already paid, a correction raises only the line it added and leaves a line that was there without an item alone';
end $$;

rollback;
