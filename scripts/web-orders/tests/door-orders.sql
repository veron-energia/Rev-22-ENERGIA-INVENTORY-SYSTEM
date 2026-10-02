-- Staff-link registrations become website orders (380, on 372, 373 and 376).
--
--   D0  380 fills each channel's door_methods once, from the one active
--       "Cash", "PayNow" and "Bank Transfer" (a name held by two methods is
--       left out), leaves a channel that has them alone, and running it again
--       changes nothing; it stops when a price function it relies on is not
--       production's.
--   D1  A registration that adds up is recorded with what the form said: the
--       OFF id, the registration time, the names, the method, reference, date
--       paid and Registered by. On a live channel it is still not invoiced.
--   D2  The same registration again returns what was kept and changes nothing.
--   D3  The early bird follows the date paid.
--   D4  Each reason a registration waits for a Manager, at its limits: the
--       amount, a date paid after today or more than 60 days before the
--       registration, a registration time in the future, a possible repeat
--       (same phone, pass and people within 24 hours), an inactive Registered
--       by (no one credited); several at once are all listed.
--   D5  Refusals: an off channel (kept as refused, like 'paid'), a malformed id,
--       an unknown channel, an incomplete form, another provider (not kept),
--       and an id another channel holds.
--   D6  Create invoice: the channel's store, raised by its profile, dated on
--       the date paid (never after today) and priced by it (early bird), paid
--       with the form's method and reference (else the OFF id), the total equal
--       to the amount paid, Registered by as service staff and as the guests'
--       registered_by, the guests named as on the form, a new buyer made with
--       the channel's source, or the one customer with the phone; audited.
--   D7  What stops Create invoice: an amount that is not the price (nothing is
--       left behind), a method the channel does not have, two customers with
--       the phone (candidates; a Manager chooses).
--   D8  Link existing invoice: the preview and its warnings, read-only; the link
--       (the invoice and its guests unchanged, audited); every refusal; a
--       staff-link registration refused while the channel was off is linked
--       to the invoice made by hand for it.
--   D9  Dismiss and restore: a reason, never invoiced or linked while
--       dismissed, restored as recorded or as waiting when the arrival checks
--       now fail; a dismissed one is no one's repeat; staff-link orders only.
--   D10 Who may do what.
--   D11 web_orders_list and event_guest_list show the new fields; the guest
--       list's invoice fields only at stores the person works in; an order's
--       email only for a guest with the name the order gave.
--   D12 web_order_sync: the event, the orders (not refused, not test) with
--       their invoices and people, the counter sales (no website order's), the
--       free guests (382; free-guests.sql checks them in full), and at most
--       once a minute, holding its channel without FOR UPDATE.
--   D13 web_order_staff: active staff who can be credited, by name, id and
--       name only.
--   D14 Online orders are untouched: a Stripe order still invoices at payment;
--       neither 'paid' nor 'names' reaches a staff-link order, and nothing but
--       a Manager invoices one.
--   D15 An open order names the invoices made by hand for the event with the
--       buyer's phone, without waiting for it.
--   D16 The sheet's numbers stay with each person: someone taken off keeps
--       theirs (cancelled), people added come after, an order's people keep
--       the form's from Create invoice on, and a deleted counter sale the sync
--       listed before is still listed, as deleted.
--
-- D0 runs 380 again, which puts back its own web_order_sync; 382 goes on
-- again after it, so D12 and D16 check the sync the website gets now.
--
-- Every check runs, then the file fails if any did. Disposable database only;
-- everything is rolled back. Fixtures carry a random suffix; phones are made
-- up (+65 9380 ....), names and emails are fixtures.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '120s';
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
create temp table tx(k text primary key, v text);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k=key $$;
create function pg_temp.tx(key text) returns text language sql as $$ select v from tx where k=key $$;
create function pg_temp.as_user(key text) returns void language sql as
$$ select set_config('request.jwt.claim.sub', coalesce(pg_temp.fx(key)::text, ''), true) $$;
-- The edge function calls as the service role: no user at all.
create function pg_temp.as_service() returns void language sql as
$$ select set_config('request.jwt.claim.sub', '', true) $$;
create function pg_temp.err(q text) returns text language plpgsql as
$$begin execute q; return null; exception when others then return sqlerrm; end$$;
create function pg_temp.d(n int) returns date language sql as $$ select public.sg_today() + n $$;
-- A made-up phone no customer, order or earlier pick has.
create function pg_temp.phone() returns text language sql volatile as $$
  select '+659380' || lpad(n::text, 4, '0') from generate_series(0, 9999) n
   where not exists (select 1 from public.customers c
                      where regexp_replace(coalesce(c.phone, ''), '\D', '', 'g') = '659380' || lpad(n::text, 4, '0'))
     and not exists (select 1 from public.web_orders w
                      where regexp_replace(coalesce(w.buyer_phone, ''), '\D', '', 'g') = '659380' || lpad(n::text, 4, '0'))
     and not exists (select 1 from tx where regexp_replace(tx.v, '\D', '', 'g') = '659380' || lpad(n::text, 4, '0'))
   order by random() limit 1
$$;
create function pg_temp.off(tag text) returns text language sql as
$$ select 'OFF-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || upper(substr(md5(pg_temp.tx('sfx') || tag), 1, 6)) $$;
-- One staff-link registration as the edge function hands it in. Person 1 has
-- the buyer's WhatsApp, person 2 an email of their own.
create function pg_temp.door(tag text, ticket text, qty int, cents int, paid date, method text default 'cash',
  phone text default null, staff uuid default null, registered timestamptz default null, ref text default null,
  channel text default null) returns jsonb language sql as
$$ select jsonb_build_object('channel', coalesce(channel, pg_temp.tx('channel')), 'provider', 'door', 'order_id', pg_temp.off(tag),
     'ticket', ticket, 'quantity', qty, 'amount_total_cents', cents, 'paid_on', paid::text, 'method', method,
     'reference', ref, 'staff_id', staff, 'registered_at', coalesce(registered, now()),
     'buyer', jsonb_build_object('first_name', 'Door', 'last_name', tag, 'email', 'door-' || lower(tag) || '@tests.invalid',
                                 'whatsapp', phone),
     'attendees', (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('name', 'Door ' || tag || ' ' || k,
                                      'email', case when k = 2 then 'guest-' || lower(tag) || '@tests.invalid' end,
                                      'whatsapp', case when k = 1 then phone end)) order by k)
                     from generate_series(1, qty) k)) $$;
create function pg_temp.arrive(j jsonb) returns jsonb language sql as $$ select public.web_order_door(j) $$;
create function pg_temp.order_of(sess text) returns public.web_orders language sql as
$$ select * from public.web_orders where stripe_session_id = sess $$;
create function pg_temp.oid_of(tag text) returns uuid language sql as
$$ select id from public.web_orders where stripe_session_id = pg_temp.off(tag) $$;
create function pg_temp.inv_of(tag text) returns public.invoices language sql as
$$ select i.* from public.invoices i join public.web_orders w on w.invoice_id = i.id where w.stripe_session_id = pg_temp.off(tag) $$;
-- A ticket invoice made by hand at the counter, as the current user.
create function pg_temp.sell(store text, cust uuid, opt text, days date[], names text[], bdate date) returns uuid language sql as
$$ select public.create_invoice_with_details(pg_temp.fx(store), cust, jsonb_build_array(jsonb_build_object(
     'kind', 'event_ticket', 'event_ticket_option_id', pg_temp.fx(opt), 'quantity', cardinality(names),
     'event_days', to_jsonb(days),
     'attendees', (select jsonb_agg(jsonb_build_object('name', n) order by k) from unnest(names) with ordinality u(n, k)))),
     jsonb_build_object('business_date', bdate::text)) $$;
create function pg_temp.pay(inv uuid, method text, amount numeric) returns jsonb language sql as
$$ select public.record_invoice_payment(inv, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx(method),
     'amount', amount)), gen_random_uuid()) $$;
create function pg_temp.fn_md5s() returns text language sql as
$$ select string_agg(md5(prosrc), ',' order by oid::regprocedure::text) from pg_proc where oid in (
     'public.web_order_make_invoice(uuid,uuid,boolean,boolean)'::regprocedure, 'public.web_order_resolve(uuid,uuid,boolean)'::regprocedure,
     'public.web_orders_list(uuid)'::regprocedure, 'public.web_order_names(jsonb)'::regprocedure,
     'public.event_guest_list(uuid)'::regprocedure) $$;

-- ═════ Fixtures ═════
do $$
declare sfx text := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  u uuid; k text; st uuid; st2 uuid; ev uuid; ev2 uuid; o1 uuid; o2 uuid; src uuid; pm uuid;
begin
  insert into tx values ('sfx', sfx), ('channel', 'd380-' || lower(sfx)), ('channel2', 'd380o-' || lower(sfx));
  foreach k in array array['owner','acting','manager','manager2','staff','seller','quitter','admin','invmgr'] loop
    u := gen_random_uuid();
    insert into auth.users(id, email) values (u, 'd380-' || k || '-' || lower(sfx) || '@tests.invalid');
    insert into profiles(id, full_name, email, role, is_active)
    values (u, 'D380 ' || initcap(k) || ' ' || sfx, 'd380-' || k || '-' || lower(sfx) || '@tests.invalid',
            case k when 'owner' then 'owner' when 'acting' then 'owner' when 'manager' then 'manager'
                   when 'manager2' then 'manager' when 'admin' then 'admin' when 'invmgr' then 'inventory_manager'
                   else 'staff' end::user_role,
            k <> 'quitter');
    insert into fx values (k, u);
  end loop;
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  insert into stores(name, code, country_code) values ('D380 Van ' || sfx, 'D380V' || sfx, 'SG') returning id into st;
  insert into stores(name, code, country_code) values ('D380 Shop ' || sfx, 'D380S' || sfx, 'SG') returning id into st2;
  insert into fx values ('van', st), ('shop', st2);
  insert into user_store_assignments(user_id, store_id) values
    (pg_temp.fx('manager'), st), (pg_temp.fx('staff'), st), (pg_temp.fx('seller'), st), (pg_temp.fx('manager2'), st2);
  -- Early bird (50%) ends yesterday; the event is in a week.
  ev := public.event_save(jsonb_build_object('name', 'D380 Birthday ' || sfx,
    'early_bird_until', pg_temp.d(-1), 'early_bird_percent', 50,
    'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(7)), jsonb_build_object('day', pg_temp.d(8))),
    'store_ids', jsonb_build_array(st),
    'options', jsonb_build_array(jsonb_build_object('name', '1 Day', 'days_count', 1, 'price', 61),
                                 jsonb_build_object('name', '2 Days', 'days_count', 2, 'price', 94))));
  select id into o1 from public.event_ticket_options where event_id = ev and name = '1 Day';
  select id into o2 from public.event_ticket_options where event_id = ev and name = '2 Days';
  insert into fx values ('ev', ev), ('one', o1), ('two', o2);
  ev2 := public.event_save(jsonb_build_object('name', 'D380 Other ' || sfx,
    'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(9))), 'store_ids', jsonb_build_array(st2),
    'options', jsonb_build_array(jsonb_build_object('name', 'Entry', 'days_count', 1, 'price', 10))));
  insert into fx values ('ev2', ev2), ('entry', (select id from public.event_ticket_options where event_id = ev2));
  insert into customer_source_options(label, is_active, requires_details, sort_order)
  values ('D380 Event ' || sfx, true, true, 9999) returning id into src;
  insert into fx values ('src', src), ('stripe', (select id from public.payment_methods where name = 'Stripe (online)'));
  -- Exactly one active "Cash" and "PayNow"; "Bank Transfer" under two
  -- spellings, so it is left out.
  update public.payment_methods set is_active = false where lower(btrim(name)) in ('cash', 'paynow', 'bank transfer');
  foreach k in array array['Cash', 'PayNow', 'Bank Transfer', 'bank transfer'] loop
    insert into public.payment_methods(name, is_active) values (k, true)
    on conflict (name) do update set is_active = true, deleted_at = null returning id into pm;
    insert into fx values (case k when 'Cash' then 'cash' when 'PayNow' then 'paynow' when 'Bank Transfer' then 'bank' else 'bank_lc' end, pm);
  end loop;
  insert into public.web_order_channels (key, event_id, ticket_map, store_id, acting_profile_id, payment_method_id,
                                         source_option_id, source_details, mode)
  values (pg_temp.tx('channel'), ev, jsonb_build_object(
            'both', jsonb_build_object('option_id', o2, 'days', jsonb_build_array(pg_temp.d(7), pg_temp.d(8))),
            'day1', jsonb_build_object('option_id', o1, 'days', jsonb_build_array(pg_temp.d(7))),
            'day2', jsonb_build_object('option_id', o1, 'days', jsonb_build_array(pg_temp.d(8)))),
          st, pg_temp.fx('acting'), pg_temp.fx('stripe'), src, 'D380 Birthday (website)', 'live');
  -- A second channel whose methods were already chosen.
  insert into public.web_order_channels (key, event_id, ticket_map, store_id, acting_profile_id, payment_method_id, mode, door_methods)
  values (pg_temp.tx('channel2'), ev2, jsonb_build_object('day1', jsonb_build_object('option_id', pg_temp.fx('entry'),
            'days', jsonb_build_array(pg_temp.d(9)))), st2, pg_temp.fx('acting'), pg_temp.fx('stripe'), 'live',
          jsonb_build_object('cash', pg_temp.fx('paynow')));
  insert into tx values ('md5_before', pg_temp.fn_md5s());
end $$;

-- ═════ D0 The channel's methods ═════
\ir ../../../supabase/380_seminar_staff_link_orders.sql
select pg_temp.check((select door_methods from public.web_order_channels where key = pg_temp.tx('channel'))
                       = jsonb_build_object('cash', pg_temp.fx('cash'), 'paynow', pg_temp.fx('paynow')),
  'D0 380 maps cash and PayNow to the one active method of that name, and leaves out Bank Transfer (two methods)');
select pg_temp.check((select door_methods from public.web_order_channels where key = pg_temp.tx('channel2'))
                       = jsonb_build_object('cash', pg_temp.fx('paynow')),
  'D0 a channel whose methods were already chosen is left alone');
select pg_temp.check(pg_temp.fn_md5s() = pg_temp.tx('md5_before'),
  'D0 running 380 again leaves the functions it replaced as they were');
-- A price function that is not production's stops 380 before it changes
-- anything. Each run changes one, applies 380 carrying on past errors (its
-- guard's is the one expected ERROR), keeps that error and undoes it all.
create function pg_temp.touch(fn regprocedure) returns void language plpgsql as
$$begin execute regexp_replace(pg_get_functiondef(fn), '\$function\$\s*$', E'-- changed\n$function$'); end$$;
\set ON_ERROR_STOP off
\set ON_ERROR_ROLLBACK on
savepoint d0_guard;
select pg_temp.touch('public.event_ticket_price(uuid,date)');
\echo 'D0: the ERROR below is expected (380 refusing a changed event_ticket_price)'
\ir ../../../supabase/380_seminar_staff_link_orders.sql
\set d0_price :LAST_ERROR_MESSAGE
rollback to savepoint d0_guard;
select pg_temp.touch('public.event_ticket_price_date(date)');
\echo 'D0: the ERROR below is expected (380 refusing a changed event_ticket_price_date)'
\ir ../../../supabase/380_seminar_staff_link_orders.sql
\set d0_date :LAST_ERROR_MESSAGE
rollback to savepoint d0_guard;
release savepoint d0_guard;
\set ON_ERROR_ROLLBACK off
\set ON_ERROR_STOP on
select pg_temp.check(:'d0_price' = '380: public.event_ticket_price(uuid,date) is not the version this was tested against'
    and :'d0_date' = '380: public.event_ticket_price_date(date) is not the version this was tested against'
    and pg_temp.fn_md5s() = pg_temp.tx('md5_before'),
  'D0 380 stops when the price of a pass (event_ticket_price, event_ticket_price_date) is not production''s');
-- 382: the free guests in the sync, over 380's web_order_sync.
\ir ../../../supabase/382_free_guests_in_the_sync.sql

-- ═════ D1 Recorded ═════
select pg_temp.as_service();
do $$ declare r jsonb; begin
  insert into tx values ('ph_a', pg_temp.phone());
  insert into tx values ('reg_a', (now() - interval '1 minute')::text);
  r := pg_temp.arrive(pg_temp.door('A', 'day1', 2, 12200, pg_temp.d(0), 'cash', pg_temp.tx('ph_a'), pg_temp.fx('seller'),
         pg_temp.tx('reg_a')::timestamptz, ' Receipt 12 '));
  insert into tx values ('a', r::text);
end $$;
select pg_temp.check(pg_temp.tx('a')::jsonb = jsonb_build_object('status', 'recorded', 'invoice_no', null, 'review_reason', null),
  'D1 a registration that adds up is recorded: {status, invoice_no, review_reason}');
select pg_temp.check((select (o.provider, o.stripe_payment_intent, o.livemode, o.ticket, o.quantity, o.unit_amount_cents,
                              o.amount_total_cents, o.early_bird, o.door_method, o.payment_reference, o.staff_profile_id, o.paid_on,
                              o.invoice_id, o.channel)
                             is not distinct from ('door', null::text, true, 'day1', 2, 6100, 12200, false, 'cash', 'Receipt 12', pg_temp.fx('seller'),
                                pg_temp.d(0), null::uuid, pg_temp.tx('channel'))
                        from pg_temp.order_of(pg_temp.off('A')) o),
  'D1 it keeps the OFF id, the pass, the amount (and its per-person share), the method, reference, date paid and Registered by');
select pg_temp.check((select o.checkout_opened_at = pg_temp.tx('reg_a')::timestamptz and o.paid_at = o.checkout_opened_at
                             and o.names_at is not null
                             and (o.buyer_name, o.buyer_first_name, o.buyer_last_name, o.buyer_email, o.buyer_phone)
                                 = ('Door A', 'Door', 'A', 'door-a@tests.invalid', pg_temp.tx('ph_a'))
                             and o.attendees = jsonb_build_array(jsonb_build_object('name', 'Door A 1', 'whatsapp', pg_temp.tx('ph_a')),
                                                                 jsonb_build_object('name', 'Door A 2', 'email', 'guest-a@tests.invalid'))
                        from pg_temp.order_of(pg_temp.off('A')) o),
  'D1 the registration time is the checkout''s and the payment''s, and the buyer and names are kept as ''names'' keeps them');
select pg_temp.check((select mode from public.web_order_channels where key = pg_temp.tx('channel')) = 'live'
    and not exists (select 1 from public.invoices where notes like '%' || pg_temp.off('A') || '%'),
  'D1 on a live channel it is still not invoiced');

-- ═════ D2 Nothing twice ═════
do $$ declare r jsonb; begin
  insert into tx values ('a_updated', (select updated_at::text from pg_temp.order_of(pg_temp.off('A'))));
  r := pg_temp.arrive(pg_temp.door('A', 'day1', 2, 999, pg_temp.d(-1), 'bank', pg_temp.phone(), null, now()));
  insert into tx values ('a_again', r::text);
end $$;
select pg_temp.check(pg_temp.tx('a_again')::jsonb = pg_temp.tx('a')::jsonb
    and (select (amount_total_cents, door_method, paid_on, updated_at::text, staff_profile_id)
                = (12200, 'cash', pg_temp.d(0), pg_temp.tx('a_updated'), pg_temp.fx('seller'))
           from pg_temp.order_of(pg_temp.off('A')))
    and (select count(*) from public.web_orders where stripe_session_id = pg_temp.off('A')) = 1,
  'D2 the same OFF id again returns what was kept and changes nothing');

-- ═════ D3 The early bird follows the date paid ═════
do $$ declare r jsonb; begin
  insert into tx values ('ph_b', pg_temp.phone()), ('ph_c', pg_temp.phone());
  r := pg_temp.arrive(pg_temp.door('B', 'day1', 1, 3050, pg_temp.d(-1), 'cash', pg_temp.tx('ph_b')));
  insert into tx values ('b', r->>'status');
  r := pg_temp.arrive(pg_temp.door('C', 'day1', 1, 3050, pg_temp.d(0), 'cash', pg_temp.tx('ph_c')));
  insert into tx values ('c', r->>'status'), ('c_reason', r->>'review_reason');
end $$;
select pg_temp.check(pg_temp.tx('b') = 'recorded' and (select early_bird from pg_temp.order_of(pg_temp.off('B')))
    and pg_temp.tx('c') = 'needs_review' and not (select early_bird from pg_temp.order_of(pg_temp.off('C')))
    and pg_temp.tx('c_reason') = format('S$30.50 was paid, but 1 × "1 Day" paid on %s costs S$61.00', to_char(pg_temp.d(0), 'DD Mon YYYY')),
  'D3 paid on the last early-bird day the early-bird price adds up; paid today it waits, saying what it costs');

-- ═════ D4 Why a registration waits ═════
do $$ declare r jsonb; begin
  r := pg_temp.arrive(pg_temp.door('F1', 'day1', 1, 6100, pg_temp.d(1), 'cash', pg_temp.phone()));
  insert into tx values ('f1', r->>'status'), ('f1r', r->>'review_reason');
  r := pg_temp.arrive(pg_temp.door('F2', 'day1', 1, 3050, pg_temp.d(-61), 'cash', pg_temp.phone()));
  insert into tx values ('f2', r->>'status'), ('f2r', r->>'review_reason');
  r := pg_temp.arrive(pg_temp.door('F3', 'day1', 1, 3050, pg_temp.d(-60), 'cash', pg_temp.phone()));
  insert into tx values ('f3', r->>'status');
  r := pg_temp.arrive(pg_temp.door('F4', 'day1', 1, 6100, pg_temp.d(0), 'cash', pg_temp.phone(), null, now() + interval '6 minutes'));
  insert into tx values ('f4', r->>'status'), ('f4r', r->>'review_reason');
  r := pg_temp.arrive(pg_temp.door('F5', 'day1', 1, 6100, pg_temp.d(0), 'cash', pg_temp.phone(), null, now() + interval '4 minutes'));
  insert into tx values ('f5', r->>'status');
end $$;
select pg_temp.check(pg_temp.tx('f1') = 'needs_review'
    and pg_temp.tx('f1r') = format('The date paid (%s) is after today', to_char(pg_temp.d(1), 'DD Mon YYYY'))
    and pg_temp.tx('f2') = 'needs_review'
    and pg_temp.tx('f2r') = format('The date paid (%s) is more than 60 days before the registration', to_char(pg_temp.d(-61), 'DD Mon YYYY'))
    and pg_temp.tx('f3') = 'recorded',
  'D4 a date paid after today, or 61 days before the registration, waits; 60 days does not');
select pg_temp.check(pg_temp.tx('f4') = 'needs_review' and pg_temp.tx('f4r') = 'The registration time is in the future'
    and pg_temp.tx('f5') = 'recorded',
  'D4 a registration time 6 minutes in the future waits; 4 minutes does not');
-- Possible repeats: the same phone (however it is written), pass and people
-- within 24 hours of each other.
do $$ declare r jsonb; v text; begin
  insert into tx values ('ph_r', pg_temp.phone());
  v := pg_temp.tx('ph_r');
  r := pg_temp.arrive(pg_temp.door('R1', 'both', 2, 18800, pg_temp.d(0), 'cash', v, null, now() - interval '2 hours'));
  insert into tx values ('r1', r->>'status');
  r := pg_temp.arrive(pg_temp.door('R2', 'both', 2, 18800, pg_temp.d(0), 'paynow',
         substr(v, 1, 3) || ' ' || substr(v, 4, 4) || ' ' || substr(v, 8)));
  insert into tx values ('r2', r->>'status'), ('r2r', r->>'review_reason');
  r := pg_temp.arrive(pg_temp.door('R3', 'both', 1, 9400, pg_temp.d(0), 'cash', v));
  insert into tx values ('r3', r->>'status');
  r := pg_temp.arrive(pg_temp.door('R4', 'both', 2, 9400, pg_temp.d(-1), 'cash', v, null, now() - interval '27 hours'));
  insert into tx values ('r4', r->>'status');
  r := pg_temp.arrive(pg_temp.door('R5', 'day1', 2, 12200, pg_temp.d(0), 'cash', v));
  insert into tx values ('r5', r->>'status');
end $$;
select pg_temp.check(pg_temp.tx('r1') = 'recorded' and pg_temp.tx('r2') = 'needs_review'
    and pg_temp.tx('r2r') = 'Possibly the same as ' || pg_temp.off('R1') || ' (the same phone, pass and number of people within 24 hours)',
  'D4 the same phone, pass and people within 24 hours waits as a possible repeat, naming the other');
select pg_temp.check((pg_temp.tx('r3'), pg_temp.tx('r4'), pg_temp.tx('r5')) = ('recorded', 'recorded', 'recorded'),
  'D4 other people, more than 24 hours apart, or another pass is no repeat');
-- Registered by.
do $$ declare r jsonb; begin
  r := pg_temp.arrive(pg_temp.door('S1', 'day1', 1, 6100, pg_temp.d(0), 'cash', pg_temp.phone(), pg_temp.fx('quitter')));
  insert into tx values ('s1', r->>'status'), ('s1r', r->>'review_reason');
  r := pg_temp.arrive(pg_temp.door('S2', 'day1', 1, 6100, pg_temp.d(0), 'cash', pg_temp.phone(), gen_random_uuid()));
  insert into tx values ('s2', r->>'status'), ('s2r', r->>'review_reason');
  r := pg_temp.arrive(pg_temp.door('S3', 'day1', 1, 6100, pg_temp.d(0), 'cash', pg_temp.phone(), pg_temp.fx('admin')));
  insert into tx values ('s3', r->>'status');
  r := pg_temp.arrive(pg_temp.door('S4', 'day1', 1, 6100, pg_temp.d(0), 'cash', pg_temp.phone(), pg_temp.fx('manager')));
  insert into tx values ('s4', r->>'status');
end $$;
select pg_temp.check(pg_temp.tx('s1') = 'needs_review'
    and pg_temp.tx('s1r') = 'The staff member chosen as Registered by is not active staff, so no one is credited'
    and pg_temp.tx('s2') = 'needs_review' and pg_temp.tx('s2r') = pg_temp.tx('s1r') and pg_temp.tx('s3') = 'needs_review'
    and (select count(*) from public.web_orders where stripe_session_id in (pg_temp.off('S1'), pg_temp.off('S2'), pg_temp.off('S3'))
          and staff_profile_id is null) = 3
    and pg_temp.tx('s4') = 'recorded' and (select staff_profile_id from pg_temp.order_of(pg_temp.off('S4'))) = pg_temp.fx('manager'),
  'D4 an inactive Registered by, an unknown id or an Admin is not credited and waits; a Manager is credited');
do $$ declare r jsonb; begin
  r := pg_temp.arrive(pg_temp.door('M1', 'both', 1, 4700, pg_temp.d(1), 'cash', pg_temp.phone(), pg_temp.fx('quitter'),
         now() + interval '1 hour'));
  insert into tx values ('m1r', r->>'review_reason');
end $$;
select pg_temp.check(pg_temp.tx('m1r') = format('S$47.00 was paid, but 1 × "2 Days" paid on %s costs S$94.00', to_char(pg_temp.d(1), 'DD Mon YYYY'))
      || format('. The date paid (%s) is after today', to_char(pg_temp.d(1), 'DD Mon YYYY'))
      || '. The registration time is in the future'
      || '. The staff member chosen as Registered by is not active staff, so no one is credited',
  'D4 several reasons are all listed');

-- ═════ D5 Refusals ═════
update public.web_order_channels set mode = 'off' where key = pg_temp.tx('channel');
do $$ declare r jsonb; begin
  r := pg_temp.arrive(pg_temp.door('O1', 'day1', 1, 6100, pg_temp.d(0), 'cash', pg_temp.phone()));
  insert into tx values ('o1', r::text);
  -- An online order paid while the channel is off is refused too (D8).
  r := public.web_order_paid(jsonb_build_object('channel', pg_temp.tx('channel'), 'stripe_session_id', 'cs_live_D380F' || pg_temp.tx('sfx'),
         'stripe_payment_intent', 'pi_D380F' || pg_temp.tx('sfx'), 'livemode', true, 'ticket', 'day1', 'quantity', 1,
         'unit_amount_cents', 6100, 'amount_total_cents', 6100, 'early_bird', false,
         'buyer', jsonb_build_object('name', 'Off Online Buyer', 'email', null, 'phone', pg_temp.phone()),
         'checkout_opened_at', now() - interval '3 minutes', 'paid_at', now() - interval '1 minute'));
  insert into tx values ('s_off', r->>'status');
end $$;
update public.web_order_channels set mode = 'live' where key = pg_temp.tx('channel');
do $$ declare r jsonb; begin
  r := pg_temp.arrive(pg_temp.door('O1', 'day1', 1, 6100, pg_temp.d(0), 'cash', pg_temp.phone()));
  insert into tx values ('o1_again', r->>'status');
end $$;
select pg_temp.check(pg_temp.tx('o1')::jsonb = jsonb_build_object('status', 'refused', 'invoice_no', null,
                                                                  'review_reason', 'The website channel is off')
    and (select status from pg_temp.order_of(pg_temp.off('O1'))) = 'refused' and pg_temp.tx('o1_again') = 'refused',
  'D5 an off channel refuses a registration and keeps it as refused, as for ''paid''');
do $$ declare r jsonb; j jsonb := pg_temp.door('Q1', 'day1', 2, 12200, pg_temp.d(0), 'cash', pg_temp.phone()); begin
  r := pg_temp.arrive(j || jsonb_build_object('order_id', 'OFF-' || to_char(pg_temp.d(0), 'YYYYMMDD') || '-abc123'));
  insert into tx values ('q_case', r->>'review_reason');
  r := pg_temp.arrive(j || jsonb_build_object('order_id', 'cs_live_' || pg_temp.tx('sfx') || 'ABCDEFGH'));
  insert into tx values ('q_cs', r->>'review_reason');
  r := pg_temp.arrive(j || jsonb_build_object('channel', 'no-such-channel-' || pg_temp.tx('sfx')));
  insert into tx values ('q_chan', r->>'review_reason');
  r := pg_temp.arrive(j || jsonb_build_object('attendees', jsonb_build_array(jsonb_build_object('name', 'Only One'))));
  insert into tx values ('q_count', r->>'review_reason');
  r := pg_temp.arrive(j || jsonb_build_object('method', 'card'));
  insert into tx values ('q_method', r->>'review_reason');
  r := pg_temp.arrive(j || jsonb_build_object('buyer', jsonb_build_object('first_name', ' ', 'whatsapp', pg_temp.phone())));
  insert into tx values ('q_buyer', r->>'review_reason');
  r := pg_temp.arrive(j || jsonb_build_object('provider', 'stripe'));
  insert into tx values ('q_provider', r->>'review_reason');
  r := pg_temp.arrive(pg_temp.door('A', 'day1', 2, 12200, pg_temp.d(0), 'cash', pg_temp.tx('ph_a'), null, null, null, pg_temp.tx('channel2')));
  insert into tx values ('q_other', r->>'status'), ('q_other_r', r->>'review_reason');
end $$;
select pg_temp.check((pg_temp.tx('q_case'), pg_temp.tx('q_cs'), pg_temp.tx('q_chan'), pg_temp.tx('q_count'), pg_temp.tx('q_method'),
                      pg_temp.tx('q_buyer'), pg_temp.tx('q_provider'))
                     = ('Not a staff-link order id', 'Not a staff-link order id', 'Unknown website channel', 'The order is incomplete',
                        'The order is incomplete', 'The order is incomplete', 'Unknown payment provider')
    and not exists (select 1 from public.web_orders where stripe_session_id = pg_temp.off('Q1') or buyer_last_name = 'Q1'),
  'D5 a malformed id, an unknown channel, names for the wrong number of people, an unknown method, no buyer name or another provider is refused and not kept');
select pg_temp.check(pg_temp.tx('q_other') = 'refused' and pg_temp.tx('q_other_r') = 'The order belongs to another channel'
    and (select channel from pg_temp.order_of(pg_temp.off('A'))) = pg_temp.tx('channel'),
  'D5 an OFF id kept for one channel is refused for another');

-- ═════ D6 Create invoice ═════
select pg_temp.as_user('manager');
do $$ declare r jsonb; begin
  r := public.web_order_resolve(pg_temp.oid_of('A'));
  insert into tx values ('a_res', r->>'status'), ('a_no', r->>'invoice_no');
end $$;
select pg_temp.check(pg_temp.tx('a_res') = 'invoiced' and pg_temp.tx('a_no') like 'INV-%'
    and (select (i.store_id, i.created_by, i.business_date, i.total_amount, i.status::text, i.notes)
                = (pg_temp.fx('van'), pg_temp.fx('acting'), pg_temp.d(0), 122.00::numeric, 'paid',
                   'Website staff link · ' || pg_temp.off('A') || ' · Cash')
           from public.invoices i where i.invoice_no = pg_temp.tx('a_no')),
  'D6 a Manager''s Create invoice makes it at the channel''s store, raised by its profile, dated on the date paid, S$122.00, paid');
select pg_temp.check((select (ii.line_kind::text, ii.quantity, ii.unit_price, ii.event_days) = ('event_ticket', 2, 61.00::numeric, array[pg_temp.d(7)])
                        from public.invoice_items ii join public.invoices i on i.id = ii.invoice_id where i.invoice_no = pg_temp.tx('a_no'))
    and (select (p.payment_method_id, p.amount, p.payment_reference, (p.effective_at at time zone 'Asia/Singapore')::date)
                = (pg_temp.fx('cash'), 122.00::numeric, 'Receipt 12', pg_temp.d(0))
           from public.invoice_payments p join public.invoices i on i.id = p.invoice_id where i.invoice_no = pg_temp.tx('a_no')),
  'D6 one ticket line for the pass, and the payment with the form''s method and reference on the date paid');
select pg_temp.check((select array_agg(ss.staff_id) from public.invoice_service_staff ss join public.invoices i on i.id = ss.invoice_id
                       where i.invoice_no = pg_temp.tx('a_no')) = array[pg_temp.fx('seller')]
    and (select string_agg(g.name || '/' || g.registered_by::text || '/' || coalesce(g.phone, '-'), ' | ' order by g.line_position)
           from public.event_guests g join public.invoices i on i.id = g.invoice_id
          where i.invoice_no = pg_temp.tx('a_no') and g.status = 'registered')
         = 'Door A 1/' || pg_temp.fx('seller') || '/' || pg_temp.tx('ph_a') || ' | Door A 2/' || pg_temp.fx('seller') || '/-',
  'D6 Registered by is the invoice''s service staff and registered its guests, who are named as on the form');
select pg_temp.check((select (c.phone, c.first_name, c.last_name, c.email, c.source_option_id)
                             = (pg_temp.tx('ph_a'), 'Door', 'A', 'door-a@tests.invalid', pg_temp.fx('src'))
                        from public.customers c join public.invoices i on i.customer_id = c.id where i.invoice_no = pg_temp.tx('a_no'))
    and (select (o.status, o.customer_created, o.invoice_item_id is not null) = ('invoiced', true, true) from pg_temp.order_of(pg_temp.off('A')) o)
    and exists (select 1 from public.audit_logs where table_name = 'web_orders' and record_id = pg_temp.oid_of('A')
                  and action = 'web_order_resolved' and changed_by = pg_temp.fx('manager')),
  'D6 a new buyer is a customer with the form''s name parts and the channel''s source; the Create invoice is audited');
do $$ declare r jsonb; begin
  r := public.web_order_resolve(pg_temp.oid_of('B'));
  insert into tx values ('b_no', r->>'invoice_no');
  r := public.web_order_resolve(pg_temp.oid_of('F1'));
  insert into tx values ('f1_res', r->>'status'), ('f1_no', r->>'invoice_no');
end $$;
select pg_temp.check((select (i.business_date, i.total_amount, i.notes) = (pg_temp.d(-1), 30.50::numeric,
                              'Website staff link · ' || pg_temp.off('B') || ' · Cash · early bird')
                        from public.invoices i where i.invoice_no = pg_temp.tx('b_no'))
    and (select (p.payment_reference, (p.effective_at at time zone 'Asia/Singapore')::date) = (pg_temp.off('B'), pg_temp.d(-1))
           from public.invoice_payments p join public.invoices i on i.id = p.invoice_id where i.invoice_no = pg_temp.tx('b_no')),
  'D6 paid on the last early-bird day: dated then, at the early-bird price, the OFF id as reference when the form gave none');
select pg_temp.check(not exists (select 1 from public.invoice_service_staff ss join public.invoices i on i.id = ss.invoice_id
                                  where i.invoice_no = pg_temp.tx('b_no'))
    and (select bool_and(g.registered_by = pg_temp.fx('acting')) from public.event_guests g join public.invoices i on i.id = g.invoice_id
          where i.invoice_no = pg_temp.tx('b_no')),
  'D6 with no Registered by, no one is service staff and the channel''s profile registered the guests');
select pg_temp.check(pg_temp.tx('f1_res') = 'invoiced'
    and (select i.business_date from public.invoices i where i.invoice_no = pg_temp.tx('f1_no')) = pg_temp.d(0)
    and (select (p.effective_at at time zone 'Asia/Singapore')::date from public.invoice_payments p
           join public.invoices i on i.id = p.invoice_id where i.invoice_no = pg_temp.tx('f1_no')) = pg_temp.d(0),
  'D6 a date paid after today: the Manager who has seen why creates the invoice, dated and paid today, never later');
select pg_temp.as_user('owner');
do $$ declare c uuid; begin
  insert into tx values ('ph_e', pg_temp.phone());
  insert into customers(full_name, phone, email) values ('Existing Door Person', pg_temp.tx('ph_e'), 'existing@tests.invalid') returning id into c;
  insert into fx values ('cust_e', c);
end $$;
select pg_temp.as_service();
do $$ declare r jsonb; begin
  r := pg_temp.arrive(pg_temp.door('E1', 'day2', 1, 6100, pg_temp.d(0), 'paynow', pg_temp.tx('ph_e')));
end $$;
select pg_temp.as_user('manager');
do $$ declare r jsonb; begin
  r := public.web_order_resolve(pg_temp.oid_of('E1'));
  insert into tx values ('e1_no', r->>'invoice_no');
end $$;
select pg_temp.check((select i.customer_id from public.invoices i where i.invoice_no = pg_temp.tx('e1_no')) = pg_temp.fx('cust_e')
    and not (select customer_created from pg_temp.order_of(pg_temp.off('E1')))
    and (select full_name from public.customers where id = pg_temp.fx('cust_e')) = 'Existing Door Person'
    and (select p.payment_method_id from public.invoice_payments p join public.invoices i on i.id = p.invoice_id
          where i.invoice_no = pg_temp.tx('e1_no')) = pg_temp.fx('paynow'),
  'D6 the one customer with the phone is the buyer (keeping their name); PayNow is paid with the PayNow method');

-- ═════ D7 What stops Create invoice ═════
do $$ declare r jsonb; begin
  r := public.web_order_resolve(pg_temp.oid_of('C'));
  insert into tx values ('c_res', r->>'status'), ('c_res_r', r->>'review_reason');
end $$;
select pg_temp.check(pg_temp.tx('c_res') = 'needs_review'
    and pg_temp.tx('c_res_r') = 'The invoice would be S$61.00 but S$30.50 was paid, so nothing was invoiced'
    and not exists (select 1 from public.invoices where notes like '%' || pg_temp.off('C') || '%')
    and not exists (select 1 from public.customers where phone = pg_temp.tx('ph_c')),
  'D7 an amount that is not the price is never invoiced: nothing is left behind, and the order says why');
select pg_temp.as_service();
do $$ declare r jsonb; begin
  r := pg_temp.arrive(pg_temp.door('K1', 'day1', 1, 6100, pg_temp.d(0), 'bank', pg_temp.phone(), null, null, 'Bank ref 7'));
  insert into tx values ('k1', r->>'status');
end $$;
select pg_temp.as_user('manager');
do $$ declare r jsonb; begin
  r := public.web_order_resolve(pg_temp.oid_of('K1'));
  insert into tx values ('k1_res', r->>'status'), ('k1_res_r', r->>'review_reason');
end $$;
select pg_temp.as_user('owner');
update public.web_order_channels set door_methods = door_methods || jsonb_build_object('bank', pg_temp.fx('bank'))
 where key = pg_temp.tx('channel');
select pg_temp.as_user('manager');
do $$ declare r jsonb; begin
  r := public.web_order_resolve(pg_temp.oid_of('K1'));
  insert into tx values ('k1_res2', r->>'status'), ('k1_no', r->>'invoice_no');
end $$;
select pg_temp.check(pg_temp.tx('k1') = 'recorded' and pg_temp.tx('k1_res') = 'needs_review'
    and pg_temp.tx('k1_res_r') = 'This channel has no active Bank Transfer payment method, so nothing was invoiced'
    and pg_temp.tx('k1_res2') = 'invoiced'
    and (select (p.payment_method_id, p.payment_reference) = (pg_temp.fx('bank'), 'Bank ref 7') from public.invoice_payments p
           join public.invoices i on i.id = p.invoice_id where i.invoice_no = pg_temp.tx('k1_no')),
  'D7 a method the channel does not have waits, saying so; once the channel has it, it is paid with it');
select pg_temp.as_user('owner');
do $$ declare c uuid; begin
  insert into tx values ('ph_t', pg_temp.phone());
  insert into customers(full_name, phone) values ('Door Twin One', pg_temp.tx('ph_t')) returning id into c;
  insert into fx values ('twin1', c);
  insert into customers(full_name, phone) values ('Door Twin Two', pg_temp.tx('ph_t')) returning id into c;
  insert into fx values ('twin2', c);
end $$;
select pg_temp.as_service();
do $$ declare r jsonb; begin
  r := pg_temp.arrive(pg_temp.door('T1', 'day1', 1, 6100, pg_temp.d(0), 'cash', pg_temp.tx('ph_t')));
end $$;
select pg_temp.as_user('manager');
do $$ declare r jsonb; begin
  r := public.web_order_resolve(pg_temp.oid_of('T1'));
  insert into tx values ('t1', r->>'status'), ('t1r', r->>'review_reason');
  r := public.web_order_resolve(pg_temp.oid_of('T1'), pg_temp.fx('twin2'), false);
  insert into tx values ('t1_res', r->>'status'), ('t1_no', r->>'invoice_no');
end $$;
select pg_temp.check(pg_temp.tx('t1') = 'needs_review' and pg_temp.tx('t1r') like '2 customers share%'
    and pg_temp.tx('t1_res') = 'invoiced'
    and (select customer_id from public.invoices where invoice_no = pg_temp.tx('t1_no')) = pg_temp.fx('twin2'),
  'D7 two customers with the phone: it waits with them as candidates, and the Manager chooses one');

-- ═════ D8 Link existing invoice ═════
select pg_temp.as_user('owner');
do $$ declare v uuid; c uuid; begin
  insert into customers(full_name, phone, email) values ('Hand Buyer', pg_temp.phone(), 'hand@tests.invalid') returning id into c;
  insert into fx values ('hand_cust', c);
  -- At the event's store: two people, paid in full (PayNow).
  v := pg_temp.sell('van', c, 'one', array[pg_temp.d(7)], array['Hand One', 'Hand Two'], pg_temp.d(0));
  perform pg_temp.pay(v, 'paynow', 122);
  insert into fx values ('inv_same', v);
  -- At another store: two people, S$100 of S$122 paid.
  v := pg_temp.sell('shop', c, 'one', array[pg_temp.d(7)], array['Shop One', 'Shop Two'], pg_temp.d(0));
  perform pg_temp.pay(v, 'cash', 100);
  insert into fx values ('inv_shop', v);
  v := pg_temp.sell('van', c, 'one', array[pg_temp.d(7)], array['Gone One'], pg_temp.d(0));
  update public.invoices set deleted_at = now() where id = v;
  insert into fx values ('inv_deleted', v);
  v := pg_temp.sell('van', c, 'one', array[pg_temp.d(7)], array['Cancelled One'], pg_temp.d(0));
  perform public.cancel_invoice_recorded(v, 'D380 cancel', gen_random_uuid());
  insert into fx values ('inv_cancel', v);
  v := pg_temp.sell('van', c, 'entry', array[pg_temp.d(9)], array['Other Event One'], pg_temp.d(0));
  insert into fx values ('inv_other', v);
  -- A counter sale of the event, paid in cash, that no order is linked to.
  v := pg_temp.sell('van', c, 'two', array[pg_temp.d(7), pg_temp.d(8)], array['Counter One', 'Counter Two'], pg_temp.d(0));
  perform pg_temp.pay(v, 'cash', 188);
  insert into fx values ('inv_counter', v);
end $$;
select pg_temp.as_service();
do $$ declare r jsonb; begin
  r := pg_temp.arrive(pg_temp.door('L1', 'day1', 2, 12200, pg_temp.d(0), 'paynow', pg_temp.phone()));
  r := pg_temp.arrive(pg_temp.door('L2', 'day1', 1, 6100, pg_temp.d(0), 'cash', pg_temp.phone()));
  r := pg_temp.arrive(pg_temp.door('L3', 'day1', 1, 6100, pg_temp.d(0), 'cash', pg_temp.phone()));
end $$;
create function pg_temp.no_of(key text) returns text language sql as $$ select invoice_no from public.invoices where id = pg_temp.fx(key) $$;
select pg_temp.as_user('manager');
select pg_temp.check((select (p->>'invoice_no', p->>'store', p->>'date', p->>'customer_name', (p->>'total')::numeric, (p->>'paid')::numeric,
                              p->>'methods', (p->>'people')::int, p->'warnings')
                             = (pg_temp.no_of('inv_same'), 'D380 Van ' || pg_temp.tx('sfx'), pg_temp.d(0)::text, 'Hand Buyer',
                                122.00::numeric, 122.00::numeric, 'PayNow', 2, '[]'::jsonb)
                        from public.web_order_link_preview(pg_temp.oid_of('L1'), ' ' || lower(pg_temp.no_of('inv_same')) || ' ') p),
  'D8 the preview shows the invoice (found by its number, however typed): store, date, customer, total, paid, methods and people, and no warnings when all match');
select pg_temp.check(pg_temp.err(format('select public.web_order_link_preview(%L, %L)', pg_temp.oid_of('L2'), pg_temp.no_of('inv_shop')))
                       = 'You do not have access to invoice ' || pg_temp.no_of('inv_shop'),
  'D8 a Manager cannot preview or link an invoice of a store they do not work in');
select pg_temp.as_user('owner');
select pg_temp.check((select p->'warnings' from public.web_order_link_preview(pg_temp.oid_of('L2'), pg_temp.no_of('inv_shop')) p)
                       = jsonb_build_array('The invoice total is S$122.00, but the order is for S$61.00',
                                           'The invoice is not fully paid: S$100.00 of S$122.00',
                                           'The invoice has 2 people for this event, and the order 1',
                                           'The invoice is at D380 Shop ' || pg_temp.tx('sfx') || ', not at the event''s store D380 Van ' || pg_temp.tx('sfx'))
    and (select (status, invoice_id) is not distinct from ('recorded', null::uuid) from pg_temp.order_of(pg_temp.off('L2')))
    and not exists (select 1 from public.audit_logs where record_id = pg_temp.oid_of('L2')),
  'D8 the preview warns of a different total, an unpaid balance, other people and another store, and changes nothing');
do $$ declare r jsonb; begin
  r := public.web_order_link_invoice(pg_temp.oid_of('L2'), pg_temp.no_of('inv_shop'));
  insert into tx values ('l2', r::text);
end $$;
select pg_temp.check(pg_temp.tx('l2')::jsonb = jsonb_build_object('status', 'invoiced', 'invoice_no', pg_temp.no_of('inv_shop'))
    and (select (o.status, o.invoice_id, o.customer_id, o.review_reason, o.invoice_item_id)
                is not distinct from ('invoiced', pg_temp.fx('inv_shop'), pg_temp.fx('hand_cust'), null::text,
                   (select ii.id from public.invoice_items ii where ii.invoice_id = pg_temp.fx('inv_shop')))
           from pg_temp.order_of(pg_temp.off('L2')) o),
  'D8 linking makes the order that invoice''s, for its customer and its ticket line');
select pg_temp.check((select string_agg(g.name || ':' || g.status, ',' order by g.line_position) from public.event_guests g
                       where g.invoice_id = pg_temp.fx('inv_shop')) = 'Shop One:registered,Shop Two:registered'
    and (select (total_amount, paid_amount, store_id) = (122.00::numeric, 100.00::numeric, pg_temp.fx('shop'))
           from public.invoices where id = pg_temp.fx('inv_shop'))
    and exists (select 1 from public.audit_logs a where a.table_name = 'web_orders' and a.record_id = pg_temp.oid_of('L2')
                  and a.action = 'web_order_linked' and a.changed_by = pg_temp.fx('owner')
                  and a.new_data->>'invoice_no' = pg_temp.no_of('inv_shop') and jsonb_array_length(a.new_data->'warnings') = 4),
  'D8 the invoice and its guests are unchanged (no one renamed), and the link is audited with what did not match');
select pg_temp.as_user('manager');
do $$ declare r jsonb; begin
  r := public.web_order_link_invoice(pg_temp.oid_of('L1'), pg_temp.no_of('inv_same'));
  insert into tx values ('l1', r->>'status');
end $$;
select pg_temp.check(pg_temp.tx('l1') = 'invoiced' and (select invoice_id from pg_temp.order_of(pg_temp.off('L1'))) = pg_temp.fx('inv_same'),
  'D8 a Manager of the event''s store links an order to an invoice of that store');
select pg_temp.as_user('owner');
select pg_temp.check(
    pg_temp.err(format('select public.web_order_link_invoice(%L, %L)', pg_temp.oid_of('L1'), pg_temp.no_of('inv_counter')))
      = 'Only a recorded or waiting order, or a staff-link registration refused while the channel was off, can be linked to an invoice'
    and pg_temp.err(format('select public.web_order_link_invoice(%L, %L)', pg_temp.oid_of('L3'), 'INV-1999-9999'))
      = 'Invoice INV-1999-9999 was not found'
    and pg_temp.err(format('select public.web_order_link_invoice(%L, %L)', pg_temp.oid_of('L3'), pg_temp.no_of('inv_deleted')))
      = 'Invoice ' || pg_temp.no_of('inv_deleted') || ' was not found'
    and pg_temp.err(format('select public.web_order_link_invoice(%L, %L)', pg_temp.oid_of('L3'), pg_temp.no_of('inv_cancel')))
      = 'Invoice ' || pg_temp.no_of('inv_cancel') || ' is cancelled, so an order cannot be linked to it'
    and pg_temp.err(format('select public.web_order_link_invoice(%L, %L)', pg_temp.oid_of('L3'), pg_temp.no_of('inv_other')))
      = 'Invoice ' || pg_temp.no_of('inv_other') || ' has no ticket to D380 Birthday ' || pg_temp.tx('sfx')
    and pg_temp.err(format('select public.web_order_link_invoice(%L, %L)', pg_temp.oid_of('L3'), pg_temp.tx('a_no')))
      = 'Invoice ' || pg_temp.tx('a_no') || ' is already the invoice of website order ' || pg_temp.off('A')
    and pg_temp.err(format('select public.web_order_link_preview(%L, %L)', pg_temp.oid_of('L3'), pg_temp.no_of('inv_same')))
      = 'Invoice ' || pg_temp.no_of('inv_same') || ' is already the invoice of website order ' || pg_temp.off('L1')
    and (select status from pg_temp.order_of(pg_temp.off('L3'))) = 'recorded',
  'D8 refused: an order already invoiced, an unknown, deleted or cancelled invoice, one with no ticket to the event, and one that is another order''s');
-- Staff invoice by hand a registration refused while the channel was off (as
-- the Off dialog says), then link it; an online order refused then is not linked.
do $$ declare v uuid; begin
  v := pg_temp.sell('van', pg_temp.fx('hand_cust'), 'one', array[pg_temp.d(7)], array['Door O1 1'], pg_temp.d(0));
  perform pg_temp.pay(v, 'cash', 61);
  insert into fx values ('inv_off', v);
end $$;
select pg_temp.as_user('manager');
do $$ declare r jsonb; begin
  r := public.web_order_link_invoice(pg_temp.oid_of('O1'), pg_temp.no_of('inv_off'));
  insert into tx values ('o1_link', r->>'status');
end $$;
select pg_temp.check(pg_temp.tx('s_off') = 'refused' and pg_temp.tx('o1_link') = 'invoiced'
    and (select (status, invoice_id, review_reason) is not distinct from ('invoiced', pg_temp.fx('inv_off'), null::text)
           from pg_temp.order_of(pg_temp.off('O1')))
    and pg_temp.err(format('select public.web_order_link_invoice(%L, %L)',
          (select id from pg_temp.order_of('cs_live_D380F' || pg_temp.tx('sfx'))), pg_temp.no_of('inv_counter')))
        = 'Only a recorded or waiting order, or a staff-link registration refused while the channel was off, can be linked to an invoice',
  'D8 a staff-link registration refused while the channel was off is linked to the invoice made by hand for it; an online order refused then is not');

-- ═════ D9 Dismiss and restore ═════
select pg_temp.as_service();
do $$ declare r jsonb; begin
  r := pg_temp.arrive(pg_temp.door('X1', 'day2', 1, 6100, pg_temp.d(0), 'cash', pg_temp.phone()));
end $$;
select pg_temp.as_user('manager');
select pg_temp.check(pg_temp.err(format('select public.web_order_dismiss(%L, %L)', pg_temp.oid_of('X1'), ' ab '))
                       = 'Give the reason for dismissing it (at least 3 characters)',
  'D9 dismissing needs a reason');
do $$ declare r jsonb; begin
  r := public.web_order_dismiss(pg_temp.oid_of('X1'), ' Test registration ');
  insert into tx values ('x1', r::text);
end $$;
select pg_temp.check(pg_temp.tx('x1')::jsonb = jsonb_build_object('status', 'dismissed', 'invoice_no', null, 'review_reason', 'Test registration')
    and (select (status, review_reason) = ('dismissed', 'Test registration') from pg_temp.order_of(pg_temp.off('X1')))
    and exists (select 1 from public.audit_logs where record_id = pg_temp.oid_of('X1') and action = 'web_order_dismissed'
                  and changed_by = pg_temp.fx('manager') and reason = 'Test registration' and old_data->>'status' = 'recorded'),
  'D9 a Manager dismisses a registration with the reason, audited');
select pg_temp.check(pg_temp.err(format('select public.web_order_resolve(%L)', pg_temp.oid_of('X1')))
                       = 'A dismissed order is not invoiced. Restore it first'
    and pg_temp.err(format('select public.web_order_link_invoice(%L, %L)', pg_temp.oid_of('X1'), pg_temp.no_of('inv_counter')))
      = 'Only a recorded or waiting order, or a staff-link registration refused while the channel was off, can be linked to an invoice',
  'D9 a dismissed registration is neither invoiced nor linked');
select pg_temp.as_service();
select pg_temp.check((pg_temp.arrive(pg_temp.door('X1', 'day2', 1, 6100, pg_temp.d(0), 'cash', pg_temp.phone())))->>'status' = 'dismissed',
  'D9 the website sending it again is told it was dismissed');
select pg_temp.as_user('manager');
do $$ declare r jsonb; begin
  r := public.web_order_dismiss(pg_temp.oid_of('X1'), null, false);
  insert into tx values ('x1_back', r::text);
  -- C waits for its amount (and its Create invoice said so); dismissed and
  -- restored, it waits for its amount again.
  r := public.web_order_dismiss(pg_temp.oid_of('C'), 'Checking with the customer');
  r := public.web_order_dismiss(pg_temp.oid_of('C'), 'Found it', false);
  insert into tx values ('c_back', r::text);
end $$;
select pg_temp.check(pg_temp.tx('x1_back')::jsonb = jsonb_build_object('status', 'recorded', 'invoice_no', null, 'review_reason', null)
    and exists (select 1 from public.audit_logs where record_id = pg_temp.oid_of('X1') and action = 'web_order_restored'
                  and old_data->>'review_reason' = 'Test registration')
    and pg_temp.tx('c_back')::jsonb->>'status' = 'needs_review'
    and pg_temp.tx('c_back')::jsonb->>'review_reason' = pg_temp.tx('c_reason'),
  'D9 restored, it is recorded again, or waits when the arrival checks now find a reason; audited');
do $$ declare r jsonb; begin
  r := public.web_order_dismiss(pg_temp.oid_of('R1'), 'Duplicate of R2');
  r := public.web_order_dismiss(pg_temp.oid_of('R2'), 'Duplicate');
end $$;
select pg_temp.as_service();
do $$ declare r jsonb; begin
  r := pg_temp.arrive(pg_temp.door('R6', 'both', 2, 18800, pg_temp.d(0), 'cash', pg_temp.tx('ph_r')));
  insert into tx values ('r6', r->>'status');
end $$;
select pg_temp.check(pg_temp.tx('r6') = 'recorded', 'D9 a dismissed registration is no one''s possible repeat');
select pg_temp.as_service();
do $$ declare r jsonb; begin
  r := public.web_order_paid(jsonb_build_object('channel', pg_temp.tx('channel'), 'stripe_session_id', 'cs_live_D380S' || pg_temp.tx('sfx'),
         'stripe_payment_intent', 'pi_D380S' || pg_temp.tx('sfx'), 'livemode', true, 'ticket', 'day1', 'quantity', 1,
         'unit_amount_cents', 6100, 'amount_total_cents', 6100, 'early_bird', false,
         'buyer', jsonb_build_object('name', 'Online Buyer', 'email', 'online@tests.invalid', 'phone', pg_temp.phone()),
         'checkout_opened_at', now() - interval '3 minutes', 'paid_at', now() - interval '1 minute'));
  insert into tx values ('s_live', r->>'status'), ('s_live_no', r->>'invoice_no');
end $$;
select pg_temp.as_user('manager');
select pg_temp.check(
    pg_temp.err(format('select public.web_order_dismiss(%L, %L)', (select id from pg_temp.order_of('cs_live_D380S' || pg_temp.tx('sfx'))), 'Test'))
      = 'Only a staff-link registration can be dismissed'
    and pg_temp.err(format('select public.web_order_dismiss(%L, %L)', pg_temp.oid_of('A'), 'Test'))
      = 'Only a recorded or waiting registration can be dismissed'
    and pg_temp.err(format('select public.web_order_dismiss(%L, null, false)', pg_temp.oid_of('A')))
      = 'Only a dismissed registration can be restored',
  'D9 only a staff-link registration that is recorded or waiting is dismissed, and only a dismissed one restored');

-- ═════ D10 Who may do what ═════
select pg_temp.check(
    not has_function_privilege('authenticated', 'public.web_order_door(jsonb)', 'execute')
    and not has_function_privilege('authenticated', 'public.web_order_sync(text)', 'execute')
    and not has_function_privilege('authenticated', 'public.web_order_staff(text)', 'execute')
    and not has_function_privilege('anon', 'public.web_order_door(jsonb)', 'execute')
    and has_function_privilege('service_role', 'public.web_order_door(jsonb)', 'execute')
    and has_function_privilege('service_role', 'public.web_order_sync(text)', 'execute')
    and has_function_privilege('service_role', 'public.web_order_staff(text)', 'execute')
    and not has_function_privilege('authenticated', 'public.web_order_door_review(public.web_orders, public.web_order_channels)', 'execute')
    and not has_function_privilege('authenticated', 'public.web_order_invoice_people(uuid, uuid, public.web_orders, boolean)', 'execute')
    and not has_function_privilege('authenticated', 'public.web_order_link_target(public.web_orders, public.web_order_channels, text)', 'execute')
    and not has_function_privilege('authenticated', 'public.web_order_invoice_methods(uuid)', 'execute'),
  'D10 only the service role hands in registrations and asks for the sync and the staff; the rules are no one''s endpoints');
select pg_temp.check(
    has_function_privilege('authenticated', 'public.web_order_link_preview(uuid, text)', 'execute')
    and has_function_privilege('authenticated', 'public.web_order_link_invoice(uuid, text)', 'execute')
    and has_function_privilege('authenticated', 'public.web_order_dismiss(uuid, text, boolean)', 'execute')
    and not has_function_privilege('anon', 'public.web_order_link_preview(uuid, text)', 'execute')
    and not has_function_privilege('anon', 'public.web_order_link_invoice(uuid, text)', 'execute')
    and not has_function_privilege('anon', 'public.web_order_dismiss(uuid, text, boolean)', 'execute'),
  'D10 the Manager functions are for signed-in staff, not the anon key');
select pg_temp.as_user('staff');
select pg_temp.check(
    pg_temp.err(format('select public.web_order_link_preview(%L, %L)', pg_temp.oid_of('L3'), pg_temp.no_of('inv_counter'))) ~ 'Owner, Admin or Manager'
    and pg_temp.err(format('select public.web_order_link_invoice(%L, %L)', pg_temp.oid_of('L3'), pg_temp.no_of('inv_counter'))) ~ 'Owner, Admin or Manager'
    and pg_temp.err(format('select public.web_order_dismiss(%L, %L)', pg_temp.oid_of('L3'), 'Test')) ~ 'Owner, Admin or Manager'
    and pg_temp.err(format('select public.web_order_resolve(%L)', pg_temp.oid_of('L3'))) ~ 'Owner, Admin or Manager',
  'D10 staff neither preview, link, dismiss nor create the invoice');
select pg_temp.as_user('manager2');
select pg_temp.check(
    pg_temp.err(format('select public.web_order_link_preview(%L, %L)', pg_temp.oid_of('L3'), pg_temp.no_of('inv_counter'))) ~ 'access'
    and pg_temp.err(format('select public.web_order_link_invoice(%L, %L)', pg_temp.oid_of('L3'), pg_temp.no_of('inv_counter'))) ~ 'access'
    and pg_temp.err(format('select public.web_order_dismiss(%L, %L)', pg_temp.oid_of('L3'), 'Test')) ~ 'access'
    and pg_temp.err(format('select public.web_order_resolve(%L)', pg_temp.oid_of('L3'))) ~ 'access'
    and (select status from pg_temp.order_of(pg_temp.off('L3'))) = 'recorded',
  'D10 a Manager of another store does none of them');

-- ═════ D11 What the Events page shows ═════
select pg_temp.as_user('manager');
create function pg_temp.listed(sess text) returns jsonb language sql as
$$ select x from jsonb_array_elements(public.web_orders_list(pg_temp.fx('ev'))->'orders') x where x->>'stripe_session_id' = sess $$;
select pg_temp.check((select (x->>'provider', x->>'door_method', x->>'payment_reference', x->>'paid_on', x->>'staff_profile_id', x->>'staff_name')
                             = ('door', 'cash', 'Receipt 12', pg_temp.d(0)::text, pg_temp.fx('seller')::text, 'D380 Seller ' || pg_temp.tx('sfx'))
                        from pg_temp.listed(pg_temp.off('A')) x)
    and (select x->>'status' from pg_temp.listed(pg_temp.off('X1')) x) = 'recorded'
    and (select x->>'review_reason' from pg_temp.listed(pg_temp.off('R1')) x) = 'Duplicate of R2'
    and (select (x->>'provider', x->'door_method', x->'paid_on', x->'staff_name')
                = ('stripe', 'null'::jsonb, 'null'::jsonb, 'null'::jsonb)
           from pg_temp.listed('cs_live_D380S' || pg_temp.tx('sfx')) x),
  'D11 the Website orders list shows a staff-link order''s method, reference, date paid and Registered by (none for online orders)');
select pg_temp.as_user('owner');
do $$ declare c uuid; begin
  insert into customers(full_name, phone, email) values ('Free Guest Person', pg_temp.phone(), 'free@tests.invalid') returning id into c;
  perform public.event_save_guest(jsonb_build_object('event_id', pg_temp.fx('ev'), 'name', 'Free Guest', 'customer_id', c,
            'days', jsonb_build_array(pg_temp.d(7))));
end $$;
create function pg_temp.guest(gname text) returns jsonb language sql as
$$ select x from jsonb_array_elements(public.event_guest_list(pg_temp.fx('ev'))) x where x->>'name' = gname $$;
select pg_temp.as_user('manager');
select pg_temp.check((select (x->>'email', x->>'order_id', x->>'payment_methods')
                             = ('door-a@tests.invalid', pg_temp.off('A'), 'Cash') from pg_temp.guest('Door A 1') x)
    and (select (x->>'email', x->>'order_id') = ('guest-a@tests.invalid', pg_temp.off('A')) from pg_temp.guest('Door A 2') x)
    and (select (x->>'order_id', x->>'payment_methods') = ('cs_live_D380S' || pg_temp.tx('sfx'), 'Stripe (online)')
           from pg_temp.guest('Online Buyer') x)
    and (select (x->'email', x->'order_id', x->>'payment_methods') = ('null'::jsonb, 'null'::jsonb, 'Cash')
           from pg_temp.guest('Counter One') x)
    and (select x->>'email' from pg_temp.guest('Free Guest') x) = 'free@tests.invalid',
  'D11 the guest list gives each guest''s email (the customer''s, else the form''s; none for a counter guest with no customer), website order and payment methods');
select pg_temp.check((select (x->'invoice_no', x->'email', x->'order_id', x->'payment_methods')
                             = ('null'::jsonb, 'null'::jsonb, 'null'::jsonb, 'null'::jsonb) from pg_temp.guest('Shop One') x),
  'D11 for an invoice of a store the Manager does not work in, they are out of sight like its number');
select pg_temp.as_user('owner');
select pg_temp.check((select (x->>'order_id', x->>'payment_methods', x->'email') = (pg_temp.off('L2'), 'Cash', 'null'::jsonb)
                        from pg_temp.guest('Shop One') x)
    and (select x->'email' from pg_temp.guest('Shop Two') x) = 'null'::jsonb
    and (select (x->>'order_id', x->>'email') = (pg_temp.off('O1'), 'door-o1@tests.invalid') from pg_temp.guest('Door O1 1') x),
  'D11 an Owner sees them; on a linked invoice made by hand only a guest with the name the order gave gets its email (Shop One is not the order''s Door L2 1)');

-- ═════ D12 web_order_sync ═════
select pg_temp.as_user('owner');
update public.web_order_channels set allow_test = true, mode = 'record_only' where key = pg_temp.tx('channel');
select pg_temp.as_service();
do $$ declare r jsonb; begin
  r := public.web_order_paid(jsonb_build_object('channel', pg_temp.tx('channel'), 'stripe_session_id', 'cs_test_D380T' || pg_temp.tx('sfx'),
         'stripe_payment_intent', null, 'livemode', false, 'ticket', 'day1', 'quantity', 1,
         'unit_amount_cents', 6100, 'amount_total_cents', 6100, 'early_bird', false,
         'buyer', jsonb_build_object('name', 'Test Buyer', 'email', null, 'phone', pg_temp.phone()),
         'checkout_opened_at', now() - interval '3 minutes', 'paid_at', now() - interval '1 minute'));
  insert into tx values ('test_status', r->>'status');
end $$;
update public.web_order_channels set allow_test = false, mode = 'live' where key = pg_temp.tx('channel');
update public.web_order_channels set last_sync_at = null where key = pg_temp.tx('channel');
do $$ declare r jsonb; begin
  r := public.web_order_sync(pg_temp.tx('channel'));
  insert into tx values ('sync', r::text);
  r := public.web_order_sync(pg_temp.tx('channel'));
  insert into tx values ('sync_again', r::text);
  r := public.web_order_sync('no-such-channel-' || pg_temp.tx('sfx'));
  insert into tx values ('sync_unknown', r::text);
end $$;
create function pg_temp.synced(id text) returns jsonb language sql as
$$ select x from jsonb_array_elements(pg_temp.tx('sync')::jsonb->'orders') x where x->>'order_id' = id $$;
create function pg_temp.counter(no text) returns jsonb language sql as
$$ select x from jsonb_array_elements(pg_temp.tx('sync')::jsonb->'counter') x where x->>'invoice_no' = no $$;
select pg_temp.check(pg_temp.tx('test_status') = 'recorded'
    and (select array_agg(k order by k) from jsonb_object_keys(pg_temp.tx('sync')::jsonb) k) = array['counter','event','free','orders','status']
    and pg_temp.tx('sync')::jsonb->>'status' = 'ok'
    and pg_temp.tx('sync')::jsonb->'event' = jsonb_build_object('name', 'D380 Birthday ' || pg_temp.tx('sfx'),
                                                                'days', jsonb_build_array(pg_temp.d(7)::text, pg_temp.d(8)::text)),
  'D12 a sync answers ok with the event (name and days)');
select pg_temp.check((select array_agg(x->>'name') from jsonb_array_elements(pg_temp.tx('sync')::jsonb->'free') x) = array['Free Guest']
    and (select (x->>'phone', x->>'email', x->>'status', x->'days')
                = ((select c.phone from public.customers c join public.event_guests g on g.customer_id = c.id
                     where g.event_id = pg_temp.fx('ev') and g.source = 'free'),
                   'free@tests.invalid', 'registered', jsonb_build_array(pg_temp.d(7)::text))
           from jsonb_array_elements(pg_temp.tx('sync')::jsonb->'free') x),
  'D12 (382) the event''s free guest comes too, with their customer''s phone and email; the ticket people do not');
select pg_temp.check((select x - 'people' from pg_temp.synced(pg_temp.off('A')) x)
                       = jsonb_build_object('order_id', pg_temp.off('A'), 'provider', 'door', 'status', 'invoiced',
                           'invoice_no', pg_temp.tx('a_no'), 'invoice_status', 'paid', 'date', pg_temp.d(0)::text,
                           'buyer_name', 'Door A', 'buyer_phone', pg_temp.tx('ph_a'), 'buyer_email', 'door-a@tests.invalid',
                           'ticket', 'day1', 'quantity', 2, 'method', 'Cash', 'reference', 'Receipt 12',
                           'staff_name', 'D380 Seller ' || pg_temp.tx('sfx'))
    and (select x->'people' from pg_temp.synced(pg_temp.off('A')) x)
        = jsonb_build_array(
            jsonb_build_object('position', 1, 'name', 'Door A 1', 'phone', pg_temp.tx('ph_a'), 'email', 'door-a@tests.invalid',
                               'days', jsonb_build_array(pg_temp.d(7)::text), 'status', 'registered'),
            jsonb_build_object('position', 2, 'name', 'Door A 2', 'phone', null, 'email', 'guest-a@tests.invalid',
                               'days', jsonb_build_array(pg_temp.d(7)::text), 'status', 'registered')),
  'D12 an invoiced staff-link order comes with its invoice, method, reference, Registered by and the people on its invoice');
select pg_temp.check((select (x->>'status', x->'invoice_no', x->'people'->0->>'name', x->'people'->0->>'status',
                              x->'people'->0->'days')
                             = ('dismissed', 'null'::jsonb, 'Door R1 1', 'cancelled',
                                jsonb_build_array(pg_temp.d(7)::text, pg_temp.d(8)::text))
                        from pg_temp.synced(pg_temp.off('R1')) x)
    and (select x->>'status' from pg_temp.synced(pg_temp.off('L3')) x) = 'recorded'
    and (select x->'people' from pg_temp.synced(pg_temp.off('L3')) x)
        = jsonb_build_array(jsonb_build_object('position', 1, 'name', 'Door L3 1',
            'phone', (select buyer_phone from pg_temp.order_of(pg_temp.off('L3'))), 'email', 'door-l3@tests.invalid',
            'days', jsonb_build_array(pg_temp.d(7)::text), 'status', 'registered'))
    and (select (x->>'invoice_no', x->'people'->1->>'name') = (pg_temp.no_of('inv_shop'), 'Shop Two') from pg_temp.synced(pg_temp.off('L2')) x)
    and (select (x->>'method', x->>'reference', x->>'provider') = ('Stripe', 'pi_D380S' || pg_temp.tx('sfx'), 'stripe')
           from pg_temp.synced('cs_live_D380S' || pg_temp.tx('sfx')) x),
  'D12 a dismissed order''s people are cancelled; a recorded one''s are its names; a linked one''s are its invoice''s; online orders say their provider');
select pg_temp.check(pg_temp.synced('cs_live_D380F' || pg_temp.tx('sfx')) is null and pg_temp.synced('cs_test_D380T' || pg_temp.tx('sfx')) is null
    and (select (x->>'status', x->>'invoice_no') = ('invoiced', pg_temp.no_of('inv_off')) from pg_temp.synced(pg_temp.off('O1')) x)
    and not exists (select 1 from jsonb_array_elements(pg_temp.tx('sync')::jsonb->'orders') x
                     where x->>'order_id' not in (select stripe_session_id from public.web_orders where channel = pg_temp.tx('channel'))),
  'D12 refused and test orders are left out (a refused registration linked since is in), and only this channel''s orders are in');
select pg_temp.check((select x - 'people' from pg_temp.counter(pg_temp.no_of('inv_counter')) x)
                       = jsonb_build_object('invoice_no', pg_temp.no_of('inv_counter'), 'invoice_status', 'paid', 'date', pg_temp.d(0)::text,
                           'customer_name', 'Hand Buyer', 'phone', (select phone from public.customers where id = pg_temp.fx('hand_cust')),
                           'email', 'hand@tests.invalid', 'methods', 'Cash', 'staff_name', 'D380 Owner ' || pg_temp.tx('sfx'))
    and (select x->'people'->1 from pg_temp.counter(pg_temp.no_of('inv_counter')) x)
        = jsonb_build_object('position', 2, 'name', 'Counter Two', 'phone', null, 'email', null,
                             'days', jsonb_build_array(pg_temp.d(7)::text, pg_temp.d(8)::text), 'status', 'registered',
                             'registered_by', 'D380 Owner ' || pg_temp.tx('sfx')),
  'D12 a ticket sold at the counter comes as a counter sale: invoice, customer, methods, staff and its people with who registered them');
select pg_temp.check((select x->>'invoice_status' from pg_temp.counter(pg_temp.no_of('inv_cancel')) x) = 'cancelled'
    and (select x->'people'->0->>'status' from pg_temp.counter(pg_temp.no_of('inv_cancel')) x) = 'cancelled'
    and pg_temp.counter(pg_temp.no_of('inv_deleted')) is null
    and pg_temp.counter(pg_temp.no_of('inv_other')) is null
    and pg_temp.counter(pg_temp.tx('a_no')) is null and pg_temp.counter(pg_temp.no_of('inv_same')) is null
    and pg_temp.counter(pg_temp.no_of('inv_shop')) is null and pg_temp.counter(pg_temp.tx('s_live_no')) is null,
  'D12 a cancelled counter sale says so; an invoice deleted before any sync listed it, other events and every website order''s invoice (made or linked) are not counter sales');
select pg_temp.check(pg_temp.tx('sync_again')::jsonb = jsonb_build_object('status', 'too_soon')
    and pg_temp.tx('sync_unknown')::jsonb = jsonb_build_object('status', 'refused'),
  'D12 a second sync within a minute is too_soon and carries nothing; an unknown channel is refused');
update public.web_order_channels set last_sync_at = now() - interval '61 seconds' where key = pg_temp.tx('channel');
do $$ begin insert into tx values ('sync_later', public.web_order_sync(pg_temp.tx('channel'))->>'status'); end $$;
select pg_temp.check(pg_temp.tx('sync_later') = 'ok'
    and (select last_sync_at from public.web_order_channels where key = pg_temp.tx('channel')) = now(),
  'D12 a minute later it syncs again, and remembers when');
-- Every new order takes a key-share lock on its channel (the foreign key);
-- FOR UPDATE would make a sync wait for, and hold up, each one.
select pg_temp.check(pg_get_functiondef('public.web_order_sync(text)'::regprocedure) ~* 'where key = p_channel for no key update;'
    and pg_get_functiondef('public.web_order_sync(text)'::regprocedure) !~* 'p_channel for (update|share)',
  'D12 a sync holds its channel with FOR NO KEY UPDATE, which never waits on an order being made');

-- ═════ D13 web_order_staff ═════
do $$ declare r jsonb; begin
  r := public.web_order_staff(pg_temp.tx('channel'));
  insert into tx values ('staff', r::text);
end $$;
select pg_temp.check(pg_temp.tx('staff')::jsonb->>'status' = 'ok'
    and (select bool_and(x->>'id' in (select v::text from fx where k in ('owner','acting','manager','manager2','staff','seller')))
           from jsonb_array_elements(pg_temp.tx('staff')::jsonb->'staff') x where x->>'name' like 'D380 %' || pg_temp.tx('sfx'))
    and (select count(*) from jsonb_array_elements(pg_temp.tx('staff')::jsonb->'staff') x where x->>'name' like 'D380 %' || pg_temp.tx('sfx')) = 6
    and (select bool_and((select array_agg(k order by k) from jsonb_object_keys(x) k) = array['id','name'])
           from jsonb_array_elements(pg_temp.tx('staff')::jsonb->'staff') x)
    and (select array_agg(lower(x->>'name') order by n) = array_agg(lower(x->>'name') order by lower(x->>'name'), x->>'id')
           from jsonb_array_elements(pg_temp.tx('staff')::jsonb->'staff') with ordinality t(x, n))
    and public.web_order_staff('no-such-channel-' || pg_temp.tx('sfx'))->>'status' = 'refused',
  'D13 the staff list is the active Owners, Managers and Staff (not inactive staff, Admins or inventory managers), by name, id and name only');

-- ═════ D14 Online orders are untouched ═════
select pg_temp.check(pg_temp.tx('s_live') = 'invoiced'
    and (select (i.notes, i.store_id, i.created_by) = ('Website order · Stripe cs_live_D380S' || pg_temp.tx('sfx'), pg_temp.fx('van'), pg_temp.fx('acting'))
           from public.invoices i where i.invoice_no = pg_temp.tx('s_live_no'))
    and (select (p.payment_method_id, p.payment_reference) = (pg_temp.fx('stripe'), 'pi_D380S' || pg_temp.tx('sfx'))
           from public.invoice_payments p join public.invoices i on i.id = p.invoice_id where i.invoice_no = pg_temp.tx('s_live_no'))
    and not exists (select 1 from public.invoice_service_staff ss join public.invoices i on i.id = ss.invoice_id
                     where i.invoice_no = pg_temp.tx('s_live_no')),
  'D14 a Stripe order on the live channel is still invoiced at payment, as before');
select pg_temp.as_service();
do $$ declare r jsonb; j jsonb := jsonb_build_object('channel', pg_temp.tx('channel'), 'ticket', 'day1', 'quantity', 1,
       'unit_amount_cents', 6100, 'amount_total_cents', 6100, 'early_bird', false, 'livemode', true,
       'buyer', jsonb_build_object('name', 'Sneaky', 'phone', pg_temp.phone()),
       'checkout_opened_at', now() - interval '3 minutes', 'paid_at', now() - interval '1 minute'); begin
  insert into tx values ('l3_before', (select to_jsonb(o) - 'updated_at' from pg_temp.order_of(pg_temp.off('L3')) o)::text);
  r := public.web_order_names(jsonb_build_object('channel', pg_temp.tx('channel'), 'stripe_session_id', pg_temp.off('L3'), 'livemode', true,
         'buyer', jsonb_build_object('first_name', 'Renamed'), 'attendees', jsonb_build_array(jsonb_build_object('name', 'Renamed'))));
  insert into tx values ('n_door', r->>'status');
  r := public.web_order_paid(j || jsonb_build_object('stripe_session_id', pg_temp.off('L3'), 'provider', 'door'));
  insert into tx values ('p_door', r->>'review_reason');
  r := public.web_order_paid(j || jsonb_build_object('stripe_session_id', pg_temp.off('L3')));
  insert into tx values ('p_off', r->>'review_reason');
  r := public.web_order_make_invoice(pg_temp.oid_of('L3'));
  insert into tx values ('mk_door', r->>'status');
end $$;
select pg_temp.check(pg_temp.tx('n_door') = 'not_found' and pg_temp.tx('p_door') = 'Unknown payment provider'
    and pg_temp.tx('p_off') = 'Not a Stripe checkout id' and pg_temp.tx('mk_door') = 'recorded'
    and (select (to_jsonb(o) - 'updated_at')::text from pg_temp.order_of(pg_temp.off('L3')) o) = pg_temp.tx('l3_before')
    and not exists (select 1 from public.invoices where notes like '%' || pg_temp.off('L3') || '%'),
  'D14 neither ''names'' nor ''paid'' reaches a staff-link order, and the service role cannot invoice one');

-- ═════ D15 Invoices made by hand for the same phone ═════
select pg_temp.as_user('owner');
do $$ declare c uuid; v uuid; begin
  insert into tx values ('ph_h', pg_temp.phone());
  insert into customers(full_name, phone) values ('Prior Buyer', pg_temp.tx('ph_h')) returning id into c;
  v := pg_temp.sell('van', c, 'one', array[pg_temp.d(7)], array['Prior One'], pg_temp.d(0));
  perform pg_temp.pay(v, 'cash', 61);
  insert into fx values ('inv_prior', v);
  -- At a store the Manager does not work in, for someone else, with the
  -- phone on the guest.
  v := public.create_invoice_with_details(pg_temp.fx('shop'), pg_temp.fx('cust_e'), jsonb_build_array(jsonb_build_object(
         'kind', 'event_ticket', 'event_ticket_option_id', pg_temp.fx('one'), 'quantity', 1, 'event_days', to_jsonb(array[pg_temp.d(7)]),
         'attendees', jsonb_build_array(jsonb_build_object('name', 'Prior Shop Guest', 'phone', pg_temp.tx('ph_h'))))),
         jsonb_build_object('business_date', pg_temp.d(0)::text));
  insert into fx values ('inv_prior_shop', v);
  -- Cancelled: no longer anyone's.
  v := pg_temp.sell('van', c, 'one', array[pg_temp.d(7)], array['Prior Cancelled'], pg_temp.d(0));
  perform public.cancel_invoice_recorded(v, 'D380 cancel', gen_random_uuid());
end $$;
select pg_temp.as_service();
do $$ declare r jsonb; begin
  r := pg_temp.arrive(pg_temp.door('H1', 'day1', 1, 6100, pg_temp.d(0), 'paynow',
         '+' || substr(pg_temp.tx('ph_h'), 2, 2) || ' ' || substr(pg_temp.tx('ph_h'), 4)));
  insert into tx values ('h1', r::text);
  -- The phone of order A, whose invoice is a website order's.
  r := pg_temp.arrive(pg_temp.door('H2', 'day2', 1, 6100, pg_temp.d(0), 'cash', pg_temp.tx('ph_a')));
end $$;
select pg_temp.as_user('manager');
select pg_temp.check(pg_temp.tx('h1')::jsonb = jsonb_build_object('status', 'recorded', 'invoice_no', null, 'review_reason', null)
    and (select x->'hand_invoices' from pg_temp.listed(pg_temp.off('H1')) x)
        = jsonb_build_array(jsonb_build_object('invoice_no', pg_temp.no_of('inv_prior'), 'store', 'D380 Van ' || pg_temp.tx('sfx')),
                            jsonb_build_object('invoice_no', null, 'store', 'D380 Shop ' || pg_temp.tx('sfx')))
    and (select x->'hand_invoices' from pg_temp.listed(pg_temp.off('H2')) x) = '[]'::jsonb
    and (select x->'hand_invoices' from pg_temp.listed(pg_temp.off('A')) x) = '[]'::jsonb,
  'D15 an open order lists the invoices made by hand for the event with the buyer''s phone (the customer''s or a guest''s; a store the Manager does not work in by name only), but still arrives recorded; cancelled invoices, website orders'' invoices and invoiced orders have none');
select pg_temp.as_user('owner');
select pg_temp.check((select x->'hand_invoices'->1->>'invoice_no' from pg_temp.listed(pg_temp.off('H1')) x) = pg_temp.no_of('inv_prior_shop'),
  'D15 an Owner sees the other store''s invoice number too');

-- ═════ D16 The sheet's numbers stay with each person ═════
create function pg_temp.line_back(item uuid) returns jsonb language sql as
$$ select jsonb_build_object('kind', ii.line_kind::text, 'invoice_item_id', ii.id,
     'event_ticket_option_id', ii.event_ticket_option_id, 'quantity', ii.quantity, 'unit_price', ii.unit_price,
     'event_days', to_jsonb(ii.event_days),
     'attendees', (select jsonb_agg(jsonb_build_object('guest_id', g.id, 'name', g.name) order by g.line_position)
                     from public.event_guests g where g.invoice_item_id = ii.id and g.status = 'registered'))
   from public.invoice_items ii where ii.id = item $$;
-- A sync now, as the service role, however soon after the last.
create function pg_temp.sync_now() returns jsonb language plpgsql as
$$begin
  update public.web_order_channels set last_sync_at = null where key = pg_temp.tx('channel');
  perform pg_temp.as_service();
  return public.web_order_sync(pg_temp.tx('channel'));
end$$;
-- position:name:status of each person a sync lists for an order or a counter sale.
create function pg_temp.people(j jsonb) returns text language sql as
$$ select string_agg((p->>'position') || ':' || (p->>'name') || ':' || (p->>'status'), ', ' order by (p->>'position')::int)
     from jsonb_array_elements(j->'people') p $$;
create function pg_temp.sold(sync jsonb, no text) returns jsonb language sql as
$$ select x from jsonb_array_elements(sync->'counter') x where x->>'invoice_no' = no $$;
create function pg_temp.ordered(sync jsonb, id text) returns jsonb language sql as
$$ select x from jsonb_array_elements(sync->'orders') x where x->>'order_id' = id $$;
-- A counter sale of three, unpaid.
select pg_temp.as_user('owner');
do $$ declare v uuid; begin
  v := pg_temp.sell('van', pg_temp.fx('hand_cust'), 'one', array[pg_temp.d(7)], array['Pos One', 'Pos Two', 'Pos Three'], pg_temp.d(0));
  insert into fx values ('inv_pos', v), ('line_pos', (select id from public.invoice_items where invoice_id = v));
  insert into tx values ('pos_1', pg_temp.sold(pg_temp.sync_now(), pg_temp.no_of('inv_pos'))::text);
end $$;
-- Pos Two is taken off; the line renumbers Pos Three to 2.
select pg_temp.as_user('owner');
do $$ begin
  perform public.correct_invoice(pg_temp.fx('inv_pos'), jsonb_build_array(
    jsonb_set(jsonb_set(pg_temp.line_back(pg_temp.fx('line_pos')), '{quantity}', '2'), '{attendees}',
      (select jsonb_agg(x) from jsonb_array_elements(pg_temp.line_back(pg_temp.fx('line_pos'))->'attendees') x where x->>'name' <> 'Pos Two'))),
    '{}'::jsonb, 'D380 take one off', gen_random_uuid());
  insert into tx values ('pos_2', pg_temp.sold(pg_temp.sync_now(), pg_temp.no_of('inv_pos'))::text);
end $$;
-- Pos Four joins the line, and Pos Five comes on a new line.
select pg_temp.as_user('owner');
do $$ begin
  perform public.correct_invoice(pg_temp.fx('inv_pos'), jsonb_build_array(
    jsonb_set(jsonb_set(pg_temp.line_back(pg_temp.fx('line_pos')), '{quantity}', '3'), '{attendees}',
      pg_temp.line_back(pg_temp.fx('line_pos'))->'attendees' || '[{"name": "Pos Four"}]'::jsonb),
    jsonb_build_object('kind', 'event_ticket', 'event_ticket_option_id', pg_temp.fx('two'), 'quantity', 1,
      'event_days', to_jsonb(array[pg_temp.d(7), pg_temp.d(8)]), 'attendees', '[{"name": "Pos Five"}]'::jsonb)),
    '{}'::jsonb, 'D380 add two', gen_random_uuid());
  insert into tx values ('pos_3', pg_temp.sold(pg_temp.sync_now(), pg_temp.no_of('inv_pos'))::text);
end $$;
-- The invoice is deleted.
select pg_temp.as_user('owner');
do $$ begin
  perform public.delete_invoice(pg_temp.fx('inv_pos'));
  insert into tx values ('pos_4', pg_temp.sold(pg_temp.sync_now(), pg_temp.no_of('inv_pos'))::text);
end $$;
select pg_temp.check(pg_temp.people(pg_temp.tx('pos_1')::jsonb) = '1:Pos One:registered, 2:Pos Two:registered, 3:Pos Three:registered'
    and pg_temp.people(pg_temp.tx('pos_2')::jsonb) = '1:Pos One:registered, 2:Pos Two:cancelled, 3:Pos Three:registered',
  'D16 a person taken off a counter sale keeps their number, as cancelled, and no one after them moves up');
select pg_temp.check(pg_temp.people(pg_temp.tx('pos_3')::jsonb) like '1:Pos One:registered, 2:Pos Two:cancelled, 3:Pos Three:registered, 4:Pos %:registered, 5:Pos %:registered'
    and pg_temp.people(pg_temp.tx('pos_3')::jsonb) like '%Pos Four%' and pg_temp.people(pg_temp.tx('pos_3')::jsonb) like '%Pos Five%',
  'D16 people added later, on the line or on a new line, come after everyone listed before');
select pg_temp.check(pg_temp.tx('pos_4')::jsonb->>'invoice_status' = 'deleted'
    and pg_temp.people(pg_temp.tx('pos_4')::jsonb) like '1:Pos One:cancelled, 2:Pos Two:cancelled, 3:Pos Three:cancelled, 4:Pos %:cancelled, 5:Pos %:cancelled',
  'D16 a counter sale deleted after a sync listed it is still listed, as deleted, its people cancelled at their numbers');
-- A counter sale whose first person is taken off before any sync lists it.
select pg_temp.as_user('owner');
do $$ declare v uuid; it uuid; begin
  v := pg_temp.sell('van', pg_temp.fx('hand_cust'), 'one', array[pg_temp.d(7)], array['Pre One', 'Pre Two'], pg_temp.d(0));
  select id into it from public.invoice_items where invoice_id = v;
  insert into fx values ('inv_pre', v);
  perform public.correct_invoice(v, jsonb_build_array(
    jsonb_set(jsonb_set(pg_temp.line_back(it), '{quantity}', '1'), '{attendees}',
      (select jsonb_agg(x) from jsonb_array_elements(pg_temp.line_back(it)->'attendees') x where x->>'name' <> 'Pre One'))),
    '{}'::jsonb, 'D380 take one off early', gen_random_uuid());
  insert into tx values ('pre', pg_temp.sold(pg_temp.sync_now(), pg_temp.no_of('inv_pre'))::text);
end $$;
select pg_temp.check(pg_temp.people(pg_temp.tx('pre')::jsonb) = '1:Pre Two:registered',
  'D16 someone taken off before the sheet ever listed the invoice is not listed (the sheet never had them)');
-- A staff-link order of three; before any sync, its second person is
-- replaced on the invoice. The sheet already has the three from the form.
select pg_temp.as_service();
do $$ begin perform pg_temp.arrive(pg_temp.door('P1', 'day1', 3, 18300, pg_temp.d(0), 'cash', pg_temp.phone())); end $$;
select pg_temp.as_user('manager');
do $$ begin perform public.web_order_resolve(pg_temp.oid_of('P1')); end $$;
select pg_temp.as_user('owner');
do $$ declare it uuid := (select invoice_item_id from pg_temp.order_of(pg_temp.off('P1'))); begin
  perform public.correct_invoice((select invoice_id from pg_temp.order_of(pg_temp.off('P1'))), jsonb_build_array(
    jsonb_set(pg_temp.line_back(it), '{attendees,1}', '{"name": "Door P1 New"}'::jsonb)),
    '{}'::jsonb, 'D380 replace one', gen_random_uuid());
  insert into tx values ('p1', pg_temp.ordered(pg_temp.sync_now(), pg_temp.off('P1'))::text);
end $$;
select pg_temp.check(pg_temp.people(pg_temp.tx('p1')::jsonb)
                       = '1:Door P1 1:registered, 2:Door P1 2:cancelled, 3:Door P1 3:registered, 4:Door P1 New:registered'
    and (select jsonb_agg(p->'email' order by (p->>'position')::int) from jsonb_array_elements(pg_temp.tx('p1')::jsonb->'people') p)
        = jsonb_build_array('door-p1@tests.invalid', null, null, null),
  'D16 an order''s people keep the numbers they had on the form from its Create invoice on; the person put in at 2 is numbered 4 and gets no email meant for the one replaced');

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All staff-link order checks passed.';
end $$;
rollback;
