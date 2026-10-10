-- Events (369 + 370).
--
--   V1 Setting up: only an Owner, Admin or Manager, only at stores they work
--      in; days, stores, ticket options and the early bird are checked; a day
--      people are coming on, a sold option, or a sold option's days stay.
--   V2 A ticket on an invoice: priced by the business date (early bird on or
--      before its last day, full price after; dated back into an ended early
--      bird, the early-bird price only for a Manager), a 1-day ticket names its day,
--      a whole-event ticket takes every day, every person is named; wrong
--      days, missing names, a line voucher, an ended event or a ticket off
--      sale are refused. It is an event_ticket line with its name, no stock.
--   V3 Every person on a ticket is a guest on the ticket's days, registered by
--      whoever made the invoice.
--   V4 Editing the invoice: names change in place (same guest, same
--      check-ins), a person added or taken off, a new day, the line's saved
--      price kept; a day someone has checked in on cannot be taken away; a
--      removed line cancels its people.
--   V5 A cancelled or deleted invoice cancels its people; undoing it restores
--      them.
--   V6 Event sales: an invoice dated on an event day at an event store, or
--      holding a ticket, is the event's; staff can mark or unmark one of their
--      store's invoices, and undo that.
--   V7 Guest list and door: free guests with their days, notes and who
--      registered them; a full day warns and still adds; check-in per day with
--      a code; a free guest can be cancelled, a ticket guest cannot (their
--      invoice decides); a ticket guest's days come from the invoice.
--   V8 Who sees what: staff of another store, an inventory manager and an
--      affiliate-free login see nothing; a Manager sees their stores' events.
--   V9 Credit: a ticket's purpose is "event", its category event_ticket;
--      general credit pays for it, package credit only where allowed.
--   V10 Reports and names.
--   V11 What the review of 370 found (R1-R12): names per person on unchanged
--      lines, option moves at the old price, refunds, corrections while
--      cancelled, a one-store manager's edits, audit, removed options, other
--      stores' invoices on the guest list, off-sale tickets, the report period.
--
-- Every check runs, then the file fails if any did. Disposable database only;
-- everything is rolled back. Fixtures carry a random suffix.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '120s';
-- Production's user_has_store_access (29 Sep 2026): Owners and Admins see every
-- store, anyone else only their assigned stores.
create or replace function public.user_has_store_access(target_store_id uuid)
 returns boolean language sql security definer set search_path to 'public' as $f$
  select exists (select 1 from public.profiles p
    where p.id = auth.uid() and p.is_active = true and p.role in ('owner','admin'))
  or exists (select 1 from public.user_store_assignments usa
    join public.profiles p on p.id = usa.user_id
    where usa.user_id = auth.uid() and usa.store_id = target_store_id and p.is_active = true)
$f$;
create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create temp table fx(k text primary key, v uuid);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k=key $$;
create function pg_temp.as_user(key text) returns void language sql as
$$ select set_config('request.jwt.claim.sub', pg_temp.fx(key)::text, true) $$;
-- The error a statement raises, or null when it succeeds.
create function pg_temp.err(q text) returns text language plpgsql as
$$begin execute q; return null; exception when others then return sqlerrm; end$$;
create function pg_temp.d(n int) returns date language sql as $$ select public.sg_today() + n $$;
create function pg_temp.phone() returns text language sql volatile as $$
  select '+659123' || lpad(n::text, 4, '0') from generate_series(0, 9999) n
   where not exists (select 1 from public.customers c
                      where regexp_replace(coalesce(c.phone, ''), '\D', '', 'g') = '659123' || lpad(n::text, 4, '0'))
   order by random() limit 1
$$;
-- One ticket line: the option, people named, and days (null: not sent).
create function pg_temp.ticket(opt text, names text[], days date[] default null) returns jsonb language sql as
$$ select jsonb_build_object('kind', 'event_ticket', 'event_ticket_option_id', pg_temp.fx(opt),
     'quantity', cardinality(names),
     'attendees', (select jsonb_agg(jsonb_build_object('name', n) order by k) from unnest(names) with ordinality u(n, k)))
   || case when days is null then '{}'::jsonb else jsonb_build_object('event_days', to_jsonb(days)) end $$;
create function pg_temp.sell(store text, lines jsonb, bdate date) returns uuid language sql as
$$ select public.create_invoice_with_details(pg_temp.fx(store), pg_temp.fx('cust'), lines,
     jsonb_build_object('business_date', bdate::text)) $$;
create function pg_temp.guests(inv uuid) returns text language sql as
$$ select coalesce(string_agg(g.name || ':' || g.status, ',' order by g.line_position nulls last, g.name), '')
     from public.event_guests g where g.invoice_id = inv $$;
create function pg_temp.days_of(g uuid) returns text language sql as
$$ select coalesce(string_agg(to_char(day, 'YYYY-MM-DD'), ',' order by day), '') from public.event_guest_days where guest_id = g $$;
create function pg_temp.event_of(inv uuid) returns text language sql as
$$ select coalesce((select e.name || '/' || m.source from public.event_invoice_membership(array[inv]) m
                     join public.events e on e.id = m.event_id), 'none') $$;
-- The line of an invoice as the invoice page sends it back for an edit.
create function pg_temp.line_back(item uuid) returns jsonb language sql as
$$ select jsonb_build_object('kind', ii.line_kind::text, 'invoice_item_id', ii.id,
     'event_ticket_option_id', ii.event_ticket_option_id, 'quantity', ii.quantity, 'unit_price', ii.unit_price,
     'event_days', to_jsonb(ii.event_days),
     'attendees', (select jsonb_agg(jsonb_build_object('guest_id', g.id, 'name', g.name) order by g.line_position)
                     from public.event_guests g where g.invoice_item_id = ii.id and g.status = 'registered'))
   from public.invoice_items ii where ii.id = item $$;

-- ═════ Fixtures ═════
do $$
declare sfx text := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  u uuid; k text; st uuid; st2 uuid; p uuid; cash uuid;
begin
  foreach k in array array['owner','manager','staff','other','inv_mgr','manager2'] loop
    u := gen_random_uuid();
    insert into auth.users(id, email) values (u, 'e370-' || k || '-' || lower(sfx) || '@tests.invalid');
    insert into profiles(id, full_name, email, role)
    values (u, 'E370 ' || k, 'e370-' || k || '-' || lower(sfx) || '@tests.invalid',
            case k when 'owner' then 'owner' when 'manager' then 'manager' when 'manager2' then 'manager'
                   when 'inv_mgr' then 'inventory_manager' else 'staff' end::user_role);
    insert into fx values (k, u);
  end loop;
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  insert into stores(name, code, country_code) values ('E370 Van ' || sfx, 'E370V' || sfx, 'SG') returning id into st;
  insert into stores(name, code, country_code) values ('E370 Shop ' || sfx, 'E370S' || sfx, 'SG') returning id into st2;
  insert into fx values ('van', st), ('shop', st2);
  insert into user_store_assignments(user_id, store_id) values
    (pg_temp.fx('manager'), st), (pg_temp.fx('staff'), st), (pg_temp.fx('other'), st2),
    (pg_temp.fx('inv_mgr'), st), (pg_temp.fx('manager2'), st2), (pg_temp.fx('staff'), st2);
  insert into customers(full_name, phone) values ('E370 Buyer', pg_temp.phone()) returning id into u;
  insert into fx values ('cust', u);
  insert into products(name, sku, product_type) values ('E370 Tea', 'E370-T-' || sfx, 'own') returning id into p;
  insert into fx values ('tea', p);
  insert into store_inventory(store_id, product_id, current_qty) values (st, p, 50), (st2, p, 50);
  perform set_product_prices(st, p, 20, 20, 'available');
  perform set_product_prices(st2, p, 20, 20, 'available');
  insert into payment_methods(name, is_active) values ('E370 Cash ' || sfx, true) returning id into cash;
  insert into fx values ('cash', cash);
end $$;

-- ═════ V1 Setting up ═════
select pg_temp.as_user('staff');
select pg_temp.check(pg_temp.err($q$select public.event_save(jsonb_build_object('name','x'))$q$) ~ 'Owner, Admin or Manager',
  'V1 staff cannot set up an event');
select pg_temp.as_user('manager2');
select pg_temp.check(pg_temp.err(format($q$select public.event_save(%L::jsonb)$q$, jsonb_build_object(
    'name', 'E370 Nope', 'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(0))),
    'store_ids', jsonb_build_array(pg_temp.fx('van')),
    'options', jsonb_build_array(jsonb_build_object('name', '1 Day', 'days_count', 1, 'price', 61)))))
  ~ 'stores you work in', 'V1 a manager cannot hold an event at a store they do not work in');
select pg_temp.as_user('manager');
select pg_temp.check(pg_temp.err(format($q$select public.event_save(%L::jsonb)$q$, jsonb_build_object(
    'name', 'E370 Bad', 'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(0))),
    'store_ids', jsonb_build_array(pg_temp.fx('van')),
    'options', jsonb_build_array(jsonb_build_object('name', '2 Days', 'days_count', 2, 'price', 94)))))
  ~ 'between 1 and 1', 'V1 an option cannot cover more days than the event has');
select pg_temp.check(pg_temp.err(format($q$select public.event_save(%L::jsonb)$q$, jsonb_build_object(
    'name', 'E370 Bad', 'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(0))),
    'store_ids', jsonb_build_array(pg_temp.fx('van')), 'early_bird_percent', 50,
    'options', jsonb_build_array(jsonb_build_object('name', '1 Day', 'days_count', 1, 'price', 61)))))
  ~ 'both its last day and its discount', 'V1 an early bird needs its day and its discount');
-- The main event: yesterday and today at the van, early bird until 5 days ago
-- at 50%, 1 day 61 and 2 days 94; today holds 2 people at most.
do $$ declare v uuid; begin
  v := public.event_save(jsonb_build_object(
    'name', 'E370 Birthday', 'daily_start', '10:00', 'daily_end', '19:00',
    'early_bird_until', pg_temp.d(-5), 'early_bird_percent', 50,
    'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(-1)), jsonb_build_object('day', pg_temp.d(0), 'capacity', 2)),
    'store_ids', jsonb_build_array(pg_temp.fx('van')),
    'options', jsonb_build_array(jsonb_build_object('name', '1 Day', 'days_count', 1, 'price', 61, 'sort_order', 1),
                                 jsonb_build_object('name', '2 Days', 'days_count', 2, 'price', 94, 'sort_order', 2))));
  insert into fx values ('ev', v);
  insert into fx select 'one', id from public.event_ticket_options where event_id = v and name = '1 Day';
  insert into fx select 'two', id from public.event_ticket_options where event_id = v and name = '2 Days';
  -- An event that ended a month ago, and one taken off sale.
  v := public.event_save(jsonb_build_object('name', 'E370 Old',
    'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(-30))),
    'store_ids', jsonb_build_array(pg_temp.fx('van')),
    'options', jsonb_build_array(jsonb_build_object('name', 'Entry', 'days_count', 1, 'price', 10))));
  insert into fx values ('old', v);
  insert into fx select 'old_entry', id from public.event_ticket_options where event_id = v;
  perform pg_temp.as_user('owner');
  v := public.event_save(jsonb_build_object('name', 'E370 Closed', 'is_active', false,
    'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(3))),
    'store_ids', jsonb_build_array(pg_temp.fx('shop')),
    'options', jsonb_build_array(jsonb_build_object('name', 'Entry', 'days_count', 1, 'price', 10))));
  insert into fx values ('closed', v);
  insert into fx select 'closed_entry', id from public.event_ticket_options where event_id = v;
end $$;
select pg_temp.check((select count(*) from public.event_days where event_id = pg_temp.fx('ev')) = 2
    and (select capacity from public.event_days where event_id = pg_temp.fx('ev') and day = pg_temp.d(0)) = 2
    and (select array_agg(store_id) from public.event_stores where event_id = pg_temp.fx('ev')) = array[pg_temp.fx('van')],
  'V1 a manager sets up an event with its days, capacity and store');
select pg_temp.check((select (o->>'early_bird_price')::numeric from jsonb_array_elements(public.event_summary(pg_temp.fx('ev'))->'options') o
                       where o->>'name' = '2 Days') = 47.00, 'V1 the 2-day early-bird price is 47.00');

-- ═════ V2 A ticket on an invoice ═════
-- Dated 10 days ago, during the early bird (which ended 5 days ago), and
-- recorded today. Backdated into the early bird, only an Owner, Admin or
-- Manager gets its price; for Staff a ticket is priced on today.
select pg_temp.as_user('staff');
select pg_temp.check((select (o->>'unit_price')::numeric = 94 and not (o->>'early_bird')::boolean
                        from jsonb_array_elements(public.event_ticket_options_for_sale(pg_temp.fx('van'), pg_temp.d(-10))) o
                       where (o->>'option_id')::uuid = pg_temp.fx('two')),
  'V2 staff see the full price on an invoice dated back into the early bird');
do $$ declare v uuid; begin
  v := pg_temp.sell('van', jsonb_build_array(pg_temp.ticket('two', array['Staff Backdate'])), pg_temp.d(-10));
  insert into fx values ('inv_staff_backdated', v);
end $$;
select pg_temp.check((select unit_price from public.invoice_items where invoice_id = pg_temp.fx('inv_staff_backdated')) = 94.00,
  'V2 a ticket staff put on an invoice dated back into the early bird is full price');
-- Out of the way of the counts below (a deleted invoice's people are cancelled).
update public.invoices set deleted_at = now() where id = pg_temp.fx('inv_staff_backdated');
select pg_temp.as_user('manager');
select pg_temp.check((select (o->>'unit_price')::numeric = 47 and (o->>'early_bird')::boolean
                        from jsonb_array_elements(public.event_ticket_options_for_sale(pg_temp.fx('van'), pg_temp.d(-10))) o
                       where (o->>'option_id')::uuid = pg_temp.fx('two')),
  'V2 a manager sees the early-bird price for that date');
do $$ declare v uuid; begin
  -- The manager records the early-bird sale: a 1-day ticket for yesterday for
  -- two people, and a whole-event ticket without days (it takes both).
  v := pg_temp.sell('van', jsonb_build_array(
         pg_temp.ticket('one', array['Guest A', 'Guest B'], array[pg_temp.d(-1)]),
         pg_temp.ticket('two', array['Guest C'])), pg_temp.d(-10));
  insert into fx values ('inv_eb', v);
end $$;
select pg_temp.as_user('staff');
do $$ declare v uuid; begin
  -- 2 days ago (full price), sold at the other store.
  v := pg_temp.sell('shop', jsonb_build_array(pg_temp.ticket('two', array['Guest D'], array[pg_temp.d(-1), pg_temp.d(0)])), pg_temp.d(-2));
  insert into fx values ('inv_full', v);
end $$;
select pg_temp.check((select string_agg(ii.quantity || 'x' || ii.unit_price || '=' || ii.line_total, ' ' order by ii.unit_price)
                        from public.invoice_items ii where ii.invoice_id = pg_temp.fx('inv_eb')) = '2x30.50=61.00 1x47.00=47.00'
    and (select total_amount from public.invoices where id = pg_temp.fx('inv_eb')) = 108.00,
  'V2 on or before the early-bird day a person pays half: 2 x 30.50 + 47.00');
select pg_temp.check((select unit_price from public.invoice_items where invoice_id = pg_temp.fx('inv_full')) = 94.00
    and (select business_date from public.invoices where id = pg_temp.fx('inv_full')) = pg_temp.d(-2),
  'V2 after the early-bird day a person pays full price (94.00), on the invoice''s business date');
select pg_temp.check((select event_days from public.invoice_items where invoice_id = pg_temp.fx('inv_eb') and quantity = 1)
                       = array[pg_temp.d(-1), pg_temp.d(0)]
    and (select event_days from public.invoice_items where invoice_id = pg_temp.fx('inv_eb') and quantity = 2) = array[pg_temp.d(-1)],
  'V2 a 1-day ticket keeps its day; a whole-event ticket sent without days takes every day');
select pg_temp.check((select bool_and(line_kind = 'event_ticket' and product_id is null and item_name_snapshot like 'E370 Birthday — %')
                        from public.invoice_items where invoice_id = pg_temp.fx('inv_eb'))
    and not exists (select 1 from public.stock_movements where invoice_id = pg_temp.fx('inv_eb')),
  'V2 a ticket line is an event_ticket line named after the event and option, and moves no stock');
select pg_temp.check(pg_temp.err(format('select pg_temp.sell(''van'', %L::jsonb, pg_temp.d(0))',
    jsonb_build_array(pg_temp.ticket('one', array['X'])))) ~ 'Choose 1 day',
  'V2 a 1-day ticket of a 2-day event must name its day');
select pg_temp.check(pg_temp.err(format('select pg_temp.sell(''van'', %L::jsonb, pg_temp.d(0))',
    jsonb_build_array(pg_temp.ticket('one', array['X'], array[pg_temp.d(-1), pg_temp.d(0)])))) ~ 'is for 1 day',
  'V2 a 1-day ticket cannot cover two days');
select pg_temp.check(pg_temp.err(format('select pg_temp.sell(''van'', %L::jsonb, pg_temp.d(0))',
    jsonb_build_array(pg_temp.ticket('one', array['X'], array[pg_temp.d(4)])))) ~ 'not a day of',
  'V2 a day the event is not on is refused');
select pg_temp.check(pg_temp.err(format('select pg_temp.sell(''van'', %L::jsonb, pg_temp.d(0))',
    jsonb_build_array(pg_temp.ticket('two', array['X']) || jsonb_build_object('quantity', 2)))) ~ 'Name every person',
  'V2 every person on a ticket must be named');
select pg_temp.check(pg_temp.err(format('select pg_temp.sell(''van'', %L::jsonb, pg_temp.d(0))',
    jsonb_build_array(pg_temp.ticket('two', array['  '])))) ~ 'needs a name',
  'V2 a blank name is refused');
select pg_temp.check(pg_temp.err(format('select pg_temp.sell(''van'', %L::jsonb, pg_temp.d(0))',
    jsonb_build_array(pg_temp.ticket('two', array['X']) || jsonb_build_object('line_voucher_id', gen_random_uuid())))) ~ 'line voucher',
  'V2 a line voucher cannot discount a ticket');
select pg_temp.check(pg_temp.err(format('select pg_temp.sell(''van'', %L::jsonb, pg_temp.d(0))',
    jsonb_build_array(pg_temp.ticket('old_entry', array['X'])))) ~ 'ended on',
  'V2 an ended event''s tickets cannot go on a later invoice');
select pg_temp.check(pg_temp.err(format('select pg_temp.sell(''shop'', %L::jsonb, pg_temp.d(0))',
    jsonb_build_array(pg_temp.ticket('closed_entry', array['X'])))) ~ 'not on sale',
  'V2 a ticket of an event taken off sale is refused');
-- FOC on a ticket works like any line.
do $$ declare v uuid; it uuid; begin
  v := pg_temp.sell('van', jsonb_build_array(pg_temp.ticket('one', array['Guest F1', 'Guest F2'], array[pg_temp.d(-1)])
         || jsonb_build_object('foc_quantity', 1, 'foc_reason', 'E370 free')), pg_temp.d(-1));
  insert into fx values ('inv_foc', v);
end $$;
select pg_temp.check((select (foc_quantity, foc_amount, line_total) = (1, 61.00, 61.00) from public.invoice_items
                       where invoice_id = pg_temp.fx('inv_foc')),
  'V2 one of two people free (FOC): 61.00 charged, 61.00 FOC');

-- ═════ V3 Guests from tickets ═════
select pg_temp.check(pg_temp.guests(pg_temp.fx('inv_eb')) = 'Guest A:registered,Guest C:registered,Guest B:registered'
    or pg_temp.guests(pg_temp.fx('inv_eb')) = 'Guest A:registered,Guest B:registered,Guest C:registered',
  'V3 every person on the tickets is a guest');
select pg_temp.check((select bool_and(g.source = 'ticket' and g.event_id = pg_temp.fx('ev') and g.registered_by = pg_temp.fx('manager'))
                        from public.event_guests g where g.invoice_id = pg_temp.fx('inv_eb')),
  'V3 ticket guests belong to the event and were registered by whoever made the invoice');
select pg_temp.check(pg_temp.days_of((select id from public.event_guests where name = 'Guest A' and invoice_id = pg_temp.fx('inv_eb')))
                       = to_char(pg_temp.d(-1), 'YYYY-MM-DD')
    and pg_temp.days_of((select id from public.event_guests where name = 'Guest C' and invoice_id = pg_temp.fx('inv_eb')))
                       = to_char(pg_temp.d(-1), 'YYYY-MM-DD') || ',' || to_char(pg_temp.d(0), 'YYYY-MM-DD'),
  'V3 a guest comes on the ticket''s days');

-- ═════ V4 Editing the invoice ═════
do $$ declare a uuid; it uuid; lines jsonb; begin
  select id into it from public.invoice_items where invoice_id = pg_temp.fx('inv_eb') and quantity = 2;
  insert into fx values ('eb_line', it);
  select id into a from public.event_guests where invoice_item_id = it and name = 'Guest A';
  insert into fx values ('guest_a', a);
  -- Guest A checks in yesterday.
  perform public.event_check_in(a, pg_temp.d(-1), true, 'CD 1');
  -- Rename Guest A on the unchanged line.
  lines := jsonb_build_array(
    jsonb_set(pg_temp.line_back(it), '{attendees,0,name}', '"Guest A Renamed"'),
    pg_temp.line_back((select id from public.invoice_items where invoice_id = pg_temp.fx('inv_eb') and quantity = 1)));
  perform public.correct_invoice(pg_temp.fx('inv_eb'), lines, '{}'::jsonb, 'E370 rename', gen_random_uuid());
end $$;
select pg_temp.check((select name from public.event_guests where id = pg_temp.fx('guest_a')) = 'Guest A Renamed'
    and (select attended_at is not null from public.event_guest_days where guest_id = pg_temp.fx('guest_a') and day = pg_temp.d(-1)),
  'V4 a name changes in place: same guest, check-in kept');
do $$ declare lines jsonb; begin
  -- A third person on the 1-day line, keeping the price it was sold at.
  lines := jsonb_build_array(
    jsonb_set(jsonb_set(pg_temp.line_back(pg_temp.fx('eb_line')), '{quantity}', '3'), '{attendees}',
      pg_temp.line_back(pg_temp.fx('eb_line'))->'attendees' || '[{"name":"Guest E"}]'::jsonb),
    pg_temp.line_back((select id from public.invoice_items where invoice_id = pg_temp.fx('inv_eb') and quantity = 1)));
  perform public.correct_invoice(pg_temp.fx('inv_eb'), lines, '{}'::jsonb, 'E370 add', gen_random_uuid());
end $$;
select pg_temp.check((select (quantity, unit_price, line_total) = (3, 30.50, 91.50) from public.invoice_items where id = pg_temp.fx('eb_line'))
    and (select count(*) from public.event_guests where invoice_item_id = pg_temp.fx('eb_line') and status = 'registered') = 3,
  'V4 a person added to a line after the early bird keeps the line''s saved price (3 x 30.50)');
select pg_temp.check(pg_temp.err(format($q$select public.correct_invoice(%L, %L::jsonb, '{}'::jsonb, 'E370 move', gen_random_uuid())$q$,
    pg_temp.fx('inv_eb'), jsonb_build_array(
      jsonb_set(pg_temp.line_back(pg_temp.fx('eb_line')), '{event_days}', to_jsonb(array[pg_temp.d(0)])),
      pg_temp.line_back((select id from public.invoice_items where invoice_id = pg_temp.fx('inv_eb') and quantity = 1)))))
  ~ 'already checked in', 'V4 a day someone has checked in on cannot be taken off the ticket');
do $$ declare lines jsonb; begin
  -- Take Guest B off (2 people left).
  lines := jsonb_build_array(
    jsonb_set(jsonb_set(pg_temp.line_back(pg_temp.fx('eb_line')), '{quantity}', '2'), '{attendees}',
      (select jsonb_agg(x) from jsonb_array_elements(pg_temp.line_back(pg_temp.fx('eb_line'))->'attendees') x where x->>'name' <> 'Guest B')),
    pg_temp.line_back((select id from public.invoice_items where invoice_id = pg_temp.fx('inv_eb') and quantity = 1)));
  perform public.correct_invoice(pg_temp.fx('inv_eb'), lines, '{}'::jsonb, 'E370 remove', gen_random_uuid());
end $$;
select pg_temp.check((select status from public.event_guests where invoice_item_id = pg_temp.fx('eb_line') and name = 'Guest B') = 'cancelled'
    and (select quantity from public.invoice_items where id = pg_temp.fx('eb_line')) = 2,
  'V4 a person taken off the line is cancelled');
do $$ begin
  -- Remove the whole-event line.
  perform public.correct_invoice(pg_temp.fx('inv_eb'), jsonb_build_array(pg_temp.line_back(pg_temp.fx('eb_line'))),
    '{}'::jsonb, 'E370 drop', gen_random_uuid());
end $$;
select pg_temp.check((select status from public.event_guests where invoice_id = pg_temp.fx('inv_eb') and name = 'Guest C') = 'cancelled'
    and (select total_amount from public.invoices where id = pg_temp.fx('inv_eb')) = 61.00,
  'V4 a ticket line removed from the invoice cancels its people');

-- ═════ V5 Cancelled and deleted invoices ═════
update public.invoices set status = 'cancelled' where id = pg_temp.fx('inv_full');
select pg_temp.check(pg_temp.guests(pg_temp.fx('inv_full')) = 'Guest D:cancelled', 'V5 a cancelled invoice cancels its people');
update public.invoices set status = 'unpaid' where id = pg_temp.fx('inv_full');
select pg_temp.check(pg_temp.guests(pg_temp.fx('inv_full')) = 'Guest D:registered', 'V5 undoing the cancellation restores them');

-- ═════ V6 Event sales ═════
select pg_temp.as_user('staff');
do $$ begin
  insert into fx values ('inv_day', pg_temp.sell('van', jsonb_build_array(jsonb_build_object('kind','product','product_id',pg_temp.fx('tea'),'quantity',1)), pg_temp.d(0)));
  insert into fx values ('inv_shop', pg_temp.sell('shop', jsonb_build_array(jsonb_build_object('kind','product','product_id',pg_temp.fx('tea'),'quantity',1)), pg_temp.d(0)));
  insert into fx values ('inv_before', pg_temp.sell('van', jsonb_build_array(jsonb_build_object('kind','product','product_id',pg_temp.fx('tea'),'quantity',1)), pg_temp.d(-3)));
end $$;
select pg_temp.check(pg_temp.event_of(pg_temp.fx('inv_day')) = 'E370 Birthday/event_day', 'V6 a sale at the event store on an event day is the event''s');
select pg_temp.check(pg_temp.event_of(pg_temp.fx('inv_shop')) = 'none', 'V6 a sale at another store that day is not');
select pg_temp.check(pg_temp.event_of(pg_temp.fx('inv_before')) = 'none', 'V6 a sale at the event store on another day is not');
select pg_temp.check(pg_temp.event_of(pg_temp.fx('inv_full')) = 'E370 Birthday/ticket', 'V6 a ticket bought elsewhere before the event makes that invoice the event''s');
select public.set_invoice_event(pg_temp.fx('inv_day'), null, 'E370 staff lunch');
select public.set_invoice_event(pg_temp.fx('inv_shop'), pg_temp.fx('ev'), null);
select pg_temp.check(pg_temp.event_of(pg_temp.fx('inv_day')) = 'none' and pg_temp.event_of(pg_temp.fx('inv_shop')) = 'E370 Birthday/staff',
  'V6 staff can unmark an event-day sale and mark another sale as the event''s');
select public.clear_invoice_event(pg_temp.fx('inv_day'));
select pg_temp.check(pg_temp.event_of(pg_temp.fx('inv_day')) = 'E370 Birthday/event_day', 'V6 undoing it lets the date and store decide again');
select pg_temp.as_user('other');
select pg_temp.check(pg_temp.err(format('select public.set_invoice_event(%L, null, null)', pg_temp.fx('inv_day'))) ~ 'access',
  'V6 staff of another store cannot change a van invoice''s event');
select pg_temp.check((select count(*) from public.invoice_events(array[pg_temp.fx('inv_day'), pg_temp.fx('inv_shop')])) = 1,
  'V6 the invoice list shows an event only on invoices of the person''s stores');
select pg_temp.as_user('manager');
select pg_temp.check((select string_agg(x->>'invoice_no', ',') from jsonb_array_elements(public.event_invoices(pg_temp.fx('ev'))) x)
                       !~ (select invoice_no from public.invoices where id = pg_temp.fx('inv_shop'))
    and jsonb_array_length(public.event_invoices(pg_temp.fx('ev'))) = 3,
  'V6 an event''s sales list only the invoices of stores the person works in');

-- ═════ V7 Guest list and door ═════
select pg_temp.as_user('staff');
do $$ declare r jsonb; begin
  -- Today holds 2; Guest C was cancelled, so Guest D (both days) is the only one.
  r := public.event_save_guest(jsonb_build_object('event_id', pg_temp.fx('ev'), 'name', 'Free One', 'notes', 'VEG',
         'days', jsonb_build_array(pg_temp.d(0)), 'registered_by', pg_temp.fx('manager')));
  insert into fx values ('free1', (r->>'guest_id')::uuid);
  insert into fx values ('r1_over', case when jsonb_array_length(r->'over_capacity') = 0 then pg_temp.fx('ev') end);
  r := public.event_save_guest(jsonb_build_object('event_id', pg_temp.fx('ev'), 'name', 'Free Two',
         'days', jsonb_build_array(pg_temp.d(0))));
  insert into fx values ('free2', (r->>'guest_id')::uuid);
  insert into fx values ('r2_over', case when (r->'over_capacity'->0->>'registered')::int = 3 then pg_temp.fx('ev') end);
end $$;
select pg_temp.check(pg_temp.fx('r1_over') is not null and pg_temp.fx('r2_over') is not null
    and (select status from public.event_guests where id = pg_temp.fx('free2')) = 'registered',
  'V7 a full day warns (3 of 2) and still adds the guest');
select pg_temp.check((select (source, notes, registered_by) = ('free', 'VEG', pg_temp.fx('manager'))
                        from public.event_guests where id = pg_temp.fx('free1')),
  'V7 a free guest keeps its notes and who registered them');
select pg_temp.check(pg_temp.err(format('select public.event_save_guest(%L::jsonb)', jsonb_build_object('event_id', pg_temp.fx('ev'),
    'name', 'X', 'days', jsonb_build_array(pg_temp.d(5))))) ~ 'not a day', 'V7 a free guest''s day must be an event day');
select public.event_check_in(pg_temp.fx('free1'), pg_temp.d(0), true, 'CD 7');
select pg_temp.check((select (check_in_code, checked_in_by) = ('CD 7', pg_temp.fx('staff')) and attended_at is not null
                        from public.event_guest_days where guest_id = pg_temp.fx('free1')),
  'V7 a guest is checked in for the day with its code, by whoever checked them in');
select pg_temp.check(pg_temp.err(format('select public.event_check_in(%L, %L, true, null)', pg_temp.fx('free1'), pg_temp.d(-1)))
  ~ 'not registered for', 'V7 a guest cannot be checked in on a day they are not coming');
select public.event_check_in(pg_temp.fx('free1'), pg_temp.d(0), false, null);
select pg_temp.check((select attended_at is null and check_in_code is null from public.event_guest_days where guest_id = pg_temp.fx('free1')),
  'V7 a check-in can be undone');
select public.event_set_guest_cancelled(pg_temp.fx('free2'), true, 'E370 not coming');
select pg_temp.check((select status from public.event_guests where id = pg_temp.fx('free2')) = 'cancelled', 'V7 a free guest can be cancelled');
select pg_temp.check(pg_temp.err(format('select public.event_set_guest_cancelled(%L, true, null)', pg_temp.fx('guest_a'))) ~ 'invoice',
  'V7 a ticket guest cannot be cancelled on the guest list (their invoice decides)');
select pg_temp.check(pg_temp.err(format('select public.event_save_guest(%L::jsonb)', jsonb_build_object('id', pg_temp.fx('guest_a'),
    'name', 'Guest A Renamed', 'days', jsonb_build_array(pg_temp.d(0))))) ~ 'come from their invoice',
  'V7 a ticket guest''s days cannot change on the guest list');
select public.event_save_guest(jsonb_build_object('id', pg_temp.fx('guest_a'), 'name', 'Guest A Again', 'notes', 'Free Sock'));
select pg_temp.check((select (name, notes) = ('Guest A Again', 'Free Sock') from public.event_guests where id = pg_temp.fx('guest_a')),
  'V7 a ticket guest''s name and notes can change on the guest list');
select pg_temp.check(jsonb_array_length(public.event_guest_list(pg_temp.fx('ev'))) =
                       (select count(*) from public.event_guests where event_id = pg_temp.fx('ev')),
  'V7 the guest list holds every guest of the event, cancelled ones included');

-- ═════ V8 Who sees what ═════
select pg_temp.as_user('manager2');
select pg_temp.check(pg_temp.err(format('select public.event_guest_list(%L)', pg_temp.fx('ev'))) ~ 'access'
    and not exists (select 1 from jsonb_array_elements(public.events_list()) x where (x->>'id')::uuid = pg_temp.fx('ev'))
    and exists (select 1 from jsonb_array_elements(public.events_list()) x where (x->>'id')::uuid = pg_temp.fx('closed')),
  'V8 a manager of another store does not see the van''s event, and sees their own');
select pg_temp.as_user('inv_mgr');
select pg_temp.check(pg_temp.err(format('select public.event_guest_list(%L)', pg_temp.fx('ev'))) ~ 'access'
    and jsonb_array_length(public.events_list()) = 0, 'V8 an inventory manager sees no events');
select pg_temp.check(pg_temp.err(format('select public.event_check_in(%L, %L, true, null)', pg_temp.fx('free1'), pg_temp.d(0))) ~ 'access',
  'V8 an inventory manager cannot check anyone in');
select pg_temp.as_user('staff');
select pg_temp.check(pg_temp.err('select public.report_events(null, null)') ~ 'Owner, Admin or Manager',
  'V8 staff cannot see the events report');
select pg_temp.check(pg_temp.err(format('select public.event_delete(%L, ''x'')', pg_temp.fx('old'))) ~ 'Owner, Admin or Manager',
  'V8 staff cannot delete an event');
select pg_temp.fx('eb_line') as eb_line \gset
set local role authenticated;
select pg_temp.err(format('select public.event_sync_ticket_line(%L, ''{}''::jsonb)', :'eb_line')) as e_fn,
       pg_temp.err('select count(*) from public.event_guests') as e_table \gset
reset role;
select pg_temp.check(:'e_fn' ~ 'permission denied' and :'e_table' ~ 'permission denied',
  'V8 the internal rules and the tables cannot be reached directly');

-- ═════ V9 Credit ═════
select pg_temp.check(public.invoice_line_credit_purpose('event_ticket') = 'event'
    and public.purchase_category('event') = 'event_ticket'
    and 'event_ticket' = any(public.credit_spendable_categories())
    and public.credit_policy_allows('open', 'event_ticket') and not public.credit_policy_allows('package_paid', 'event_ticket'),
  'V9 a ticket is spending category event_ticket: general credit may pay for it, package credit only where allowed');
select pg_temp.as_user('owner');
do $$ declare v uuid; begin
  perform public.grant_customer_credit(pg_temp.fx('cust'), 'paid', 100, 'opening_balance', null, pg_temp.fx('van'),
    public.sg_today(), null, 'E370 test', null, null, pg_temp.fx('owner'), null);
  v := pg_temp.sell('van', jsonb_build_array(pg_temp.ticket('one', array['Credit Guest'], array[pg_temp.d(0)])), pg_temp.d(0));
  insert into fx values ('inv_credit', v);
  perform public.record_invoice_payment(v, jsonb_build_array(jsonb_build_object('payment_method_id',
    (select id from public.payment_methods where wallet_category = 'paid' and is_system limit 1), 'amount', 61)), gen_random_uuid());
end $$;
select pg_temp.check((select status from public.invoices where id = pg_temp.fx('inv_credit')) = 'paid'
    and (select sum(amount) from public.invoice_line_credit_allocations where invoice_id = pg_temp.fx('inv_credit')) = 61,
  'V9 general wallet credit pays for a ticket');
select pg_temp.check((select 'event_ticket' = any(e.allowed_categories) from public.customer_credit_eligibility(pg_temp.fx('cust')) e limit 1),
  'V9 the credit a customer holds lists event tickets among what it can pay for');

-- ═════ V10 Reports and names ═════
select pg_temp.as_user('owner');
-- 1-day lines left: 2 people at 30.50 (early bird), 2 people with one free,
-- 1 person paid by credit.
select pg_temp.check((select (o->>'people')::int = 5 and (o->>'early_bird_people')::int = 2 and (o->>'foc_people')::int = 1
                        and (o->>'revenue')::numeric = 61.00 + 61.00 + 61.00
                        from jsonb_array_elements(public.report_events(pg_temp.d(-1), pg_temp.d(0))) r,
                             jsonb_array_elements(r->'options') o
                       where (r->>'event_id')::uuid = pg_temp.fx('ev') and o->>'name' = '1 Day'),
  'V10 the report counts 1-day tickets: people, early bird, FOC and money (cancelled invoices left out)');
select pg_temp.check((select public.invoice_item_catalogue_name(ii) from public.invoice_items ii where ii.id = pg_temp.fx('eb_line'))
                       = 'E370 Birthday — 1 Day'
    and exists (select 1 from jsonb_array_elements(public.customer_purchase_timeline(pg_temp.fx('cust'))) i,
                              jsonb_array_elements(i->'items') it where it->>'name' = 'E370 Birthday — 1 Day'),
  'V10 a ticket line is named after its event and option, also on the customer''s history');
do $$ declare v uuid; begin
  v := public.event_save(jsonb_build_object('name', 'E370 Two Days',
    'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(-1)), jsonb_build_object('day', pg_temp.d(0))),
    'store_ids', jsonb_build_array(pg_temp.fx('van')),
    'options', jsonb_build_array(jsonb_build_object('name', 'Entry', 'days_count', 1, 'price', 5))));
  insert into fx values ('ev2', v);
  perform public.event_save_guest(jsonb_build_object('event_id', v, 'name', 'Day Two Guest', 'days', jsonb_build_array(pg_temp.d(0))));
end $$;
select pg_temp.check(pg_temp.err(format('select public.event_save(%L::jsonb)', public.event_summary(pg_temp.fx('ev2'))
    || jsonb_build_object('store_ids', jsonb_build_array(pg_temp.fx('van')),
         'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(-1)))))) ~ (to_char(pg_temp.d(0), 'DD Mon YYYY') || ' cannot be removed: 1 free guest is registered for it'),
  'V1 a day people are coming on cannot be removed (415: the refusal says how many)');
select public.event_save(public.event_summary(pg_temp.fx('ev2'))
    || jsonb_build_object('store_ids', jsonb_build_array(pg_temp.fx('van')),
         'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(-1)), jsonb_build_object('day', pg_temp.d(0), 'capacity', 40)),
         'options', jsonb_build_array(jsonb_build_object('id', (public.event_summary(pg_temp.fx('ev2'))->'options'->0->>'id'),
                                                         'name', 'Entry', 'days_count', 1, 'price', 8))));
select pg_temp.check((select capacity from public.event_days where event_id = pg_temp.fx('ev2') and day = pg_temp.d(0)) = 40
    and (select price from public.event_ticket_options where event_id = pg_temp.fx('ev2')) = 8,
  'V1 a day''s capacity and an option''s price can change');
select pg_temp.check(pg_temp.err(format('select public.event_save(%L::jsonb)', public.event_summary(pg_temp.fx('ev'))
    || jsonb_build_object('store_ids', jsonb_build_array(pg_temp.fx('van')),
         'options', jsonb_build_array((select o from jsonb_array_elements(public.event_summary(pg_temp.fx('ev'))->'options') o where o->>'name' = '2 Days'))))) ~ '"1 Day" is on .*so it cannot be removed',
  'V1 a sold option cannot be removed (415: the refusal names its invoices)');
select pg_temp.check(pg_temp.err(format('select public.event_delete(%L, ''E370'')', pg_temp.fx('ev'))) ~ 'on invoices',
  'V1 an event with tickets on invoices cannot be deleted');
select public.event_delete(pg_temp.fx('closed'), 'E370 never held');
select pg_temp.check((select deleted_at is not null from public.events where id = pg_temp.fx('closed')), 'V1 an event without tickets can be deleted');

-- ═════ V11 What the review of 370 found ═════
-- A ticket line with a product beside it, sold by staff today.
select pg_temp.as_user('staff');
do $$ declare v uuid; begin
  v := pg_temp.sell('van', jsonb_build_array(pg_temp.ticket('one', array['R1', 'R2'], array[pg_temp.d(0)]),
         jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('tea'), 'quantity', 1)), pg_temp.d(0));
  insert into fx values ('inv_r', v);
  insert into fx select 'line_r', id from public.invoice_items where invoice_id = v and line_kind = 'event_ticket';
end $$;
create function pg_temp.lines_r(ticket jsonb) returns jsonb language sql as
$$ select jsonb_build_array(ticket, (select jsonb_build_object('kind', 'product', 'invoice_item_id', id, 'product_id', product_id,
     'quantity', quantity, 'unit_price', unit_price) from public.invoice_items where invoice_id = pg_temp.fx('inv_r') and line_kind = 'product')) $$;
-- 1. An unchanged line keeps one name per person.
select pg_temp.check(pg_temp.err(format($q$select public.correct_invoice(%L, %L::jsonb, '{}'::jsonb, 'x', gen_random_uuid())$q$,
    pg_temp.fx('inv_r'), pg_temp.lines_r(jsonb_set(pg_temp.line_back(pg_temp.fx('line_r')), '{attendees}',
      pg_temp.line_back(pg_temp.fx('line_r'))->'attendees' || '[{"name":"Extra"}]'::jsonb)))) ~ 'Name every person'
    and pg_temp.err(format($q$select public.correct_invoice(%L, %L::jsonb, '{}'::jsonb, 'x', gen_random_uuid())$q$,
    pg_temp.fx('inv_r'), pg_temp.lines_r(jsonb_set(pg_temp.line_back(pg_temp.fx('line_r')), '{attendees}', '[]'::jsonb)))) ~ 'Name every person',
  'R1 an unchanged ticket line cannot gain or lose names without its people changing too');
-- 2. Moving a line to another option at the old price is a price override.
select pg_temp.check(pg_temp.err(format($q$select public.correct_invoice(%L, %L::jsonb, '{}'::jsonb, 'x', gen_random_uuid())$q$,
    pg_temp.fx('inv_r'), pg_temp.lines_r(pg_temp.line_back(pg_temp.fx('line_r'))
      || jsonb_build_object('event_ticket_option_id', pg_temp.fx('two'), 'event_days', to_jsonb(array[pg_temp.d(-1), pg_temp.d(0)]))))) ~ 'Only an Owner or Manager',
  'R2 staff cannot move a line to a dearer ticket and keep the cheaper price');
-- 7. Replacing a person on an unchanged line leaves no duplicate behind.
do $$ begin
  perform public.correct_invoice(pg_temp.fx('inv_r'), pg_temp.lines_r(jsonb_set(pg_temp.line_back(pg_temp.fx('line_r')),
    '{attendees,1}', '{"name":"R3"}'::jsonb)), '{}'::jsonb, 'E370 swap', gen_random_uuid());
end $$;
select pg_temp.check((select string_agg(name || ':' || status, ',' order by name) from public.event_guests
                       where invoice_item_id = pg_temp.fx('line_r')) = 'R1:registered,R2:cancelled,R3:registered',
  'R7 a person replaced on an unchanged line is added once, and the one replaced is off the ticket');
-- 8. Every change to a ticket's people is in the audit log.
select pg_temp.check(exists (select 1 from public.audit_logs where record_id = pg_temp.fx('inv_r') and action = 'event_ticket_people_changed'
                              and new_data::text like '%R3%'),
  'R8 the change of people on a ticket is audited');
-- 3. A ticket line refunded in full cancels its people; its money leaves the report.
select pg_temp.as_user('owner');
do $$ declare pay uuid; before numeric; begin
  perform public.record_invoice_payment(pg_temp.fx('inv_r'), jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('cash'),
    'amount', (select total_amount from public.invoices where id = pg_temp.fx('inv_r')))), gen_random_uuid());
  select id into pay from public.invoice_payments where invoice_id = pg_temp.fx('inv_r');
  -- One of the two people refunded: both stay (the invoice is corrected to take one off).
  perform public.refund_invoice_recorded(pg_temp.fx('inv_r'), jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.fx('line_r'), 'amount', 61)),
    jsonb_build_array(jsonb_build_object('payment_id', pay, 'amount', 61)), '[]'::jsonb, 'E370 one ticket refunded', gen_random_uuid());
  insert into fx values ('r3_partial', case when (select count(*) from public.event_guests where invoice_item_id = pg_temp.fx('line_r')
                                                     and status = 'registered') = 2
                                             and public.event_ticket_line_money(pg_temp.fx('line_r')) = 61 then pay end);
  perform public.refund_invoice_recorded(pg_temp.fx('inv_r'), jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.fx('line_r'), 'amount', 61)),
    jsonb_build_array(jsonb_build_object('payment_id', pay, 'amount', 61)), '[]'::jsonb, 'E370 other ticket refunded', gen_random_uuid());
end $$;
select pg_temp.check(pg_temp.fx('r3_partial') is not null,
  'R3 a ticket line refunded in part keeps its people, and its money is what is left (61.00 of 122.00)');
select pg_temp.check((select status from public.invoices where id = pg_temp.fx('inv_r')) <> 'refunded'
    and (select string_agg(name || ':' || status || ':' || coalesce(cancelled_reason, ''), ',' order by name) from public.event_guests
          where invoice_item_id = pg_temp.fx('line_r') and name <> 'R2') = 'R1:cancelled:Ticket refunded,R3:cancelled:Ticket refunded'
    and public.event_ticket_line_money(pg_temp.fx('line_r')) = 0,
  'R3 a ticket line refunded in full cancels its people and brings in nothing, while the invoice stands');
-- 4. A correction while cancelled, then a reopen, brings back only who is on the line, on its days.
select pg_temp.as_user('staff');
do $$ declare v uuid; it uuid; begin
  v := pg_temp.sell('van', jsonb_build_array(pg_temp.ticket('one', array['H1', 'H2'], array[pg_temp.d(0)])), pg_temp.d(0));
  select id into it from public.invoice_items where invoice_id = v;
  insert into fx values ('inv_h', v), ('line_h', it);
  perform pg_temp.as_user('manager');
  perform public.cancel_invoice_recorded(v, 'E370 cancel', gen_random_uuid());
  perform public.correct_invoice(v, jsonb_build_array(jsonb_build_object('kind', 'event_ticket', 'invoice_item_id', it,
      'event_ticket_option_id', pg_temp.fx('one'), 'quantity', 1, 'unit_price', 61, 'event_days', to_jsonb(array[pg_temp.d(-1)]),
      'attendees', (select jsonb_agg(jsonb_build_object('guest_id', g.id, 'name', g.name)) from public.event_guests g
                     where g.invoice_item_id = it and g.name = 'H1'))), '{}'::jsonb, 'E370 one fewer, other day', gen_random_uuid());
  perform public.reopen_invoice(v, 'E370 reopen', gen_random_uuid());
end $$;
select pg_temp.check(pg_temp.guests(pg_temp.fx('inv_h')) = 'H1:registered,H2:cancelled'
    and pg_temp.days_of((select id from public.event_guests where invoice_item_id = pg_temp.fx('line_h') and name = 'H1'))
          = to_char(pg_temp.d(-1), 'YYYY-MM-DD'),
  'R4 reopening an invoice corrected while cancelled brings back the people on the line, on its days');
-- 5. A manager of one store keeps a two-store event's other store.
select pg_temp.as_user('owner');
do $$ declare v uuid; begin
  v := public.event_save(jsonb_build_object('name', 'E370 Both', 'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(2))),
    'store_ids', jsonb_build_array(pg_temp.fx('van'), pg_temp.fx('shop')),
    'options', jsonb_build_array(jsonb_build_object('name', 'E', 'days_count', 1, 'price', 5))));
  insert into fx values ('ev_both', v);
  perform pg_temp.as_user('manager');
  perform public.event_save(public.event_summary(v) || jsonb_build_object('store_ids', jsonb_build_array(pg_temp.fx('van')), 'notes', 'E370 edited'));
end $$;
select pg_temp.check((select count(*) from public.event_stores where event_id = pg_temp.fx('ev_both')) = 2
    and (select notes from public.events where id = pg_temp.fx('ev_both')) = 'E370 edited',
  'R5 a manager of one store edits a two-store event and the other store stays');
select pg_temp.check(pg_temp.err(format('select public.event_save(%L::jsonb)', public.event_summary(pg_temp.fx('ev_both'))
    || jsonb_build_object('store_ids', jsonb_build_array(pg_temp.fx('van'))) || jsonb_build_object('id', null, 'name', 'E370 New Both',
    'store_ids', jsonb_build_array(pg_temp.fx('van'), pg_temp.fx('shop')), 'options', jsonb_build_array(jsonb_build_object('name', 'E', 'days_count', 1, 'price', 5)))))
  ~ 'stores you work in', 'R5 but still cannot hold a new event at a store they do not work in');
-- 10. The guest list shows no invoice of a store the person does not work in.
select pg_temp.as_user('staff');
do $$ begin
  insert into fx values ('inv_shop_ticket', pg_temp.sell('shop', jsonb_build_array(pg_temp.ticket('one', array['Shop Buyer'], array[pg_temp.d(0)])), pg_temp.d(0)));
end $$;
select pg_temp.as_user('manager');
select pg_temp.check((select x->>'invoice_no' is null and x->>'invoice_total' is null
                        from jsonb_array_elements(public.event_guest_list(pg_temp.fx('ev'))) x where x->>'name' = 'Shop Buyer'),
  'R10 a van manager sees the shop buyer on the guest list, but not the shop invoice');
-- 9, 11. Off sale: a saved ticket can shrink but not grow; an option whose only line was removed can go.
select pg_temp.as_user('manager');
do $$ begin
  perform public.event_save(public.event_summary(pg_temp.fx('ev')) || jsonb_build_object('store_ids', jsonb_build_array(pg_temp.fx('van')), 'is_active', false));
end $$;
select pg_temp.as_user('staff');
select pg_temp.check(pg_temp.err(format($q$select public.correct_invoice(%L, %L::jsonb, '{}'::jsonb, 'x', gen_random_uuid())$q$,
    pg_temp.fx('inv_h'), jsonb_build_array(jsonb_set(jsonb_set(pg_temp.line_back(pg_temp.fx('line_h')), '{quantity}', '2'), '{attendees}',
      pg_temp.line_back(pg_temp.fx('line_h'))->'attendees' || '[{"name":"Late"}]'::jsonb)))) ~ 'no one can be added',
  'R11 once an event is off sale, no one can be added to a saved ticket');
select pg_temp.as_user('owner');
do $$ declare v uuid; ev3 uuid; opt uuid; begin
  ev3 := public.event_save(jsonb_build_object('name', 'E370 Gone', 'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(0))),
    'store_ids', jsonb_build_array(pg_temp.fx('van')),
    'options', jsonb_build_array(jsonb_build_object('name', 'A', 'days_count', 1, 'price', 5), jsonb_build_object('name', 'B', 'days_count', 1, 'price', 6))));
  select id into opt from public.event_ticket_options where event_id = ev3 and name = 'B';
  insert into fx values ('ev_gone', ev3), ('opt_gone', opt);
  v := public.create_invoice_with_details(pg_temp.fx('van'), pg_temp.fx('cust'), jsonb_build_array(jsonb_build_object('kind', 'event_ticket',
         'event_ticket_option_id', opt, 'quantity', 1, 'event_days', to_jsonb(array[pg_temp.d(0)]), 'attendees', '[{"name":"Gone"}]'::jsonb),
         jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('tea'), 'quantity', 1)), jsonb_build_object('business_date', pg_temp.d(0)::text));
  perform public.correct_invoice(v, (select jsonb_agg(jsonb_build_object('kind', 'product', 'invoice_item_id', id, 'product_id', product_id,
      'quantity', quantity, 'unit_price', unit_price)) from public.invoice_items where invoice_id = v and line_kind = 'product'),
    '{}'::jsonb, 'E370 ticket off', gen_random_uuid());
end $$;
select coalesce(pg_temp.err(format('select public.event_save(%L::jsonb)', public.event_summary(pg_temp.fx('ev_gone'))
    || jsonb_build_object('store_ids', jsonb_build_array(pg_temp.fx('van')),
         'options', jsonb_build_array((select o from jsonb_array_elements(public.event_summary(pg_temp.fx('ev_gone'))->'options') o where o->>'name' = 'A'))))), '') as r9_err \gset
select pg_temp.check(nullif(:'r9_err', '') is null
    and not exists (select 1 from public.event_ticket_options where id = pg_temp.fx('opt_gone'))
    and (select ticket_option_id from public.event_guests where name = 'Gone') is null,
  'R9 an option whose ticket line was removed can be deleted; its former guest keeps the record');
-- 12. The report period means an event day inside it.
do $$ begin
  insert into fx values ('ev_split', public.event_save(jsonb_build_object('name', 'E370 Split',
    'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(-20)), jsonb_build_object('day', pg_temp.d(20))),
    'store_ids', jsonb_build_array(pg_temp.fx('van')), 'options', jsonb_build_array(jsonb_build_object('name', 'E', 'days_count', 1, 'price', 5)))));
end $$;
select pg_temp.check(not exists (select 1 from jsonb_array_elements(public.report_events(pg_temp.d(-5), pg_temp.d(5))) x
                                  where (x->>'event_id')::uuid = pg_temp.fx('ev_split'))
    and exists (select 1 from jsonb_array_elements(public.report_events(pg_temp.d(15), pg_temp.d(25))) x
                 where (x->>'event_id')::uuid = pg_temp.fx('ev_split')),
  'R12 the events report takes an event when one of its days is in the period');

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All event checks passed.';
end $$;
rollback;
