-- The door, the guest list, the event editor and website orders (415).
--
--   D1 Check-in on two door devices (EVENTS-3): a check-in never changes one
--      already made; the second answers already_in with the time, who checked
--      the guest in and the code; only Save code changes a code (an empty one
--      clears it); Undo clears the check-in; each change is in the audit log,
--      as it was before and after; the answer names the checker. A page
--      already open (four named arguments) still works. Only active staff of
--      the event's store get in.
--   D2 The registrar (EVENTS-1): a guest whose registrar has left can still
--      be edited; a new registrar must be active staff; Not recorded clears it;
--      a save that does not name one keeps it.
--   D3 Cancel and restore (EVENTS-M2, EVENTS-6): a free guest who has checked
--      in is not cancelled; a restore drops the days the event no longer has,
--      refuses when none remain, and answers the days now over capacity.
--   D4 The editor's locks (EVENTS-5, EVENTS-9): a ticket on a deleted invoice
--      no longer holds a day or an option's days, but still holds the option;
--      each refusal says what holds it (people, invoices by number at the
--      person's stores, the others counted); whole numbers and cents;
--      event_summary says the same (ticket_lines, sold, on_any_invoice).
--   D5 Deleting an event (EVENTS-M1): not while its website channel is not
--      Off, or holds orders waiting for an invoice. A live payment refused
--      while the channel was off waits too (D7 links it); a test one does not.
--   D6 A paid website order for a ticket taken off sale (EVENTS-7) is still
--      invoiced; a hand invoice for it is not; the flag that allows it is
--      web_order_make_invoice's alone, for its own order, and is cleared after.
--      event_summary says the channel's mode.
--   D7 Linking an invoice made by hand (EVENTS-8): only an order that took
--      real money; an order refused while the channel was off, from the
--      website too.
--   D8 The migration again changes nothing; the grants.
--   D9 Which event a sale counts under (EVENTS-4, the Owner): the event the
--      ticket is for, not the event running that day; an invoice holding
--      tickets for two events counts under the one running that day there;
--      a sale with no ticket goes by its day and store; staff marking decides
--      first. As built, products on a ticket's invoice go with it (pinned:
--      the Owner is asked).
--   D10 Closing an order refunded outside the app (the Owner): an Owner or
--      Manager closes it with a reason, audited, and its event can then be
--      deleted; staff, Admins and other stores are refused; nothing else can
--      be closed; one closed by mistake is reopened as it was before (a
--      payment refused while off is refused again, so Create invoice still
--      refuses it; any other waits in Needs review), not once its event is
--      gone; the staff link's Restore does not bring back a closed one, and
--      its Dismiss refuses a reason that starts like a close's; no invoice is
--      touched; the website's sync sees it dismissed.
--   D11 The website follows On sale (EVENTS-7, the Owner): web_order_tickets
--      says which pass is on sale, and follows the ticket's On sale, the
--      event's Tickets on sale and its deletion; the service role's alone.
--
-- It needs production's schema (it applies 415 first, which checks the
-- functions it changes against production's of 9 Oct 2026; on a database
-- that has 415 already, that is a no-op). Run it like the other event suites:
--   ENERGIA_INVOICE_DB=energia_integration_test sh scripts/invoices/local-sql.sh -f scripts/events/tests/door-check-in.sql
-- Disposable database only; everything is rolled back. Fixtures carry D415
-- and a random suffix, emails @tests.invalid, phones +659123xxxx.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '180s';
\ir ../../../supabase/415_events_check_in_and_web_orders.sql

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
-- As the server (no login: pg_cron, migrations, the service role's functions).
create function pg_temp.as_server() returns void language plpgsql as
$$begin
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
  perform set_config('request.jwt.claims', '', true);
end$$;
-- As a signed-in login, the way PostgREST sets it.
create function pg_temp.as_user(key text) returns void language plpgsql as
$$begin
  perform set_config('request.jwt.claim.sub', coalesce(pg_temp.fx(key)::text, ''), true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.fx(key), 'role', 'authenticated')::text, true);
end$$;
-- Run q as that login with the authenticated role, as a page would: 'ok' and
-- the answer, or the SQLSTATE and the message.
create function pg_temp.try_as(key text, q text) returns text language plpgsql as
$$declare v text; st text; msg text;
begin
  perform pg_temp.as_user(key);
  begin
    execute 'set local role authenticated';
    execute q into v;
    execute 'reset role';
    return 'ok' || chr(9) || coalesce(v, '');
  exception when others then
    get stacked diagnostics st = returned_sqlstate, msg = message_text;
    return st || chr(9) || msg;
  end;
end$$;
create function pg_temp.err(q text) returns text language plpgsql as
$$begin execute q; return null; exception when others then return sqlerrm; end$$;
create function pg_temp.d(n int) returns date language sql as $$ select public.sg_today() + n $$;
create function pg_temp.sg(n int, hhmm text) returns timestamptz language sql as
$$ select least(((public.sg_today() + n)::text || ' ' || hhmm)::timestamp at time zone 'Asia/Singapore', now()) $$;
create function pg_temp.phone() returns text language sql volatile as $$
  select '+659123' || lpad(n::text, 4, '0') from generate_series(0, 9999) n
   where not exists (select 1 from public.customers c
                      where regexp_replace(coalesce(c.phone, ''), '\D', '', 'g') = '659123' || lpad(n::text, 4, '0'))
   order by random() limit 1
$$;
create function pg_temp.ticket(opt text, names text[], days date[] default null) returns jsonb language sql as
$$ select jsonb_build_object('kind', 'event_ticket', 'event_ticket_option_id', pg_temp.fx(opt),
     'quantity', cardinality(names),
     'attendees', (select jsonb_agg(jsonb_build_object('name', n) order by k) from unnest(names) with ordinality u(n, k)))
   || case when days is null then '{}'::jsonb else jsonb_build_object('event_days', to_jsonb(days)) end $$;
create function pg_temp.sell(store text, lines jsonb) returns uuid language sql as
$$ select public.create_invoice_with_details(pg_temp.fx(store), pg_temp.fx('cust'), lines,
     jsonb_build_object('business_date', public.sg_today()::text)) $$;
-- The audit actions of a guest's check-ins, sorted (one transaction gives them one time).
create function pg_temp.audits(g uuid) returns text language sql as
$$ select coalesce(string_agg(a.action, ',' order by a.action), '') from public.audit_logs a
    where a.table_name = 'event_guest_days' and a.record_id = g $$;
create function pg_temp.gday(g uuid, d date) returns public.event_guest_days language sql as
$$ select * from public.event_guest_days where guest_id = g and day = d $$;
-- One paid website order as the edge function hands it in.
create function pg_temp.paid(sess text, ticket text, qty int, unit_cents int, buyer text, phone text) returns jsonb language sql as
$$ select jsonb_build_object('channel', pg_temp.tx('channel'), 'stripe_session_id', sess,
     'stripe_payment_intent', 'pi_' || substr(md5(sess), 1, 24), 'livemode', sess like 'cs_live_%',
     'ticket', ticket, 'quantity', qty, 'unit_amount_cents', unit_cents, 'amount_total_cents', unit_cents * qty,
     'early_bird', false,
     'buyer', jsonb_build_object('name', buyer, 'email', 'buyer-' || substr(md5(sess), 1, 6) || '@tests.invalid', 'phone', phone),
     'checkout_opened_at', pg_temp.sg(0, '09:00'), 'paid_at', pg_temp.sg(0, '09:01')) $$;
create function pg_temp.sess(tag text) returns text language sql as
$$ select 'cs_live_D415' || tag || pg_temp.tx('sfx') $$;
create function pg_temp.order_id(sess text) returns uuid language sql as
$$ select id from public.web_orders where stripe_session_id = sess $$;

-- ═════ Fixtures ═════
do $$
declare sfx text := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  u uuid; k text; st uuid; st2 uuid; pm uuid; src uuid;
begin
  insert into tx values ('sfx', sfx), ('channel', 'd415-' || lower(sfx));
  foreach k in array array['owner','manager','admin','staff','staff2','leaver','nostaff'] loop
    u := gen_random_uuid();
    insert into auth.users(id, email) values (u, 'd415-' || k || '-' || lower(sfx) || '@tests.invalid');
    insert into fx values (k, u);
  end loop;
  insert into profiles(id, full_name, email, role, is_active)
  select f.v, 'D415 ' || f.k, 'd415-' || f.k || '-' || lower(sfx) || '@tests.invalid',
         case f.k when 'owner' then 'owner' when 'manager' then 'manager' when 'admin' then 'admin' else 'staff' end::user_role, true
    from fx f where f.k in ('owner','manager','admin','staff','staff2','leaver');
  perform pg_temp.as_server();
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  insert into stores(name, code, country_code) values ('D415 Van ' || sfx, 'D415V' || sfx, 'SG') returning id into st;
  insert into stores(name, code, country_code) values ('D415 Shop ' || sfx, 'D415S' || sfx, 'SG') returning id into st2;
  insert into fx values ('van', st), ('shop', st2);
  insert into user_store_assignments(user_id, store_id) values
    (pg_temp.fx('manager'), st), (pg_temp.fx('admin'), st), (pg_temp.fx('staff'), st), (pg_temp.fx('staff2'), st),
    (pg_temp.fx('leaver'), st);
  insert into customers(full_name, phone) values ('D415 Buyer', pg_temp.phone()) returning id into u;
  insert into fx values ('cust', u);
  insert into payment_methods(name, is_active) values ('D415 Stripe ' || sfx, true) returning id into pm;
  insert into fx values ('pm', pm);
  insert into customer_source_options(label, is_active, requires_details, sort_order)
  values ('D415 Event ' || sfx, true, true, 9999) returning id into src;
  insert into fx values ('src', src);
  -- The door event: today and tomorrow at the van; today holds 3.
  u := public.event_save(jsonb_build_object('name', 'D415 Door ' || sfx,
    'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(0), 'capacity', 3), jsonb_build_object('day', pg_temp.d(1))),
    'store_ids', jsonb_build_array(st),
    'options', jsonb_build_array(jsonb_build_object('name', '1 Day', 'days_count', 1, 'price', 61, 'sort_order', 1),
                                 jsonb_build_object('name', '2 Days', 'days_count', 2, 'price', 94, 'sort_order', 2))));
  insert into fx values ('ev', u);
  insert into fx select 'one', id from public.event_ticket_options where event_id = u and name = '1 Day';
  insert into fx select 'two', id from public.event_ticket_options where event_id = u and name = '2 Days';
end $$;

-- ═════ D1 Check-in on two door devices ═════
select pg_temp.as_user('staff');
do $$ declare r jsonb; begin
  r := public.event_save_guest(jsonb_build_object('event_id', pg_temp.fx('ev'), 'name', 'D415 Guest One',
         'days', jsonb_build_array(pg_temp.d(0), pg_temp.d(1))));
  insert into fx values ('g1', (r->>'guest_id')::uuid);
  r := public.event_save_guest(jsonb_build_object('event_id', pg_temp.fx('ev'), 'name', 'D415 Guest Two',
         'days', jsonb_build_array(pg_temp.d(0))));
  insert into fx values ('g2', (r->>'guest_id')::uuid);
end $$;

-- Device A (Staff) checks Guest One in with W12, as the page does: named arguments, no p_save_code.
select pg_temp.try_as('staff', format($q$select public.event_check_in(p_guest_id => %L, p_day => %L, p_attended => true, p_code => ' W12 ')::text$q$,
  pg_temp.fx('g1'), pg_temp.d(0))) as d1_first \gset
select pg_temp.check(split_part(:'d1_first', chr(9), 1) = 'ok', 'D1 a page already open (four named arguments) still checks in: ' || :'d1_first');
select split_part(:'d1_first', chr(9), 2)::jsonb as d1_first_j \gset
select pg_temp.check((:'d1_first_j'::jsonb->>'check_in_code') = 'W12' and (:'d1_first_j'::jsonb->>'checked_in_by')::uuid = pg_temp.fx('staff')
    and (:'d1_first_j'::jsonb->>'checked_in_by_name') = 'D415 staff' and (:'d1_first_j'::jsonb->>'changed')::boolean
    and not (:'d1_first_j'::jsonb->>'already_in')::boolean and (:'d1_first_j'::jsonb->>'attended_at') is not null,
  'D1 a check-in answers its time, the code, and who checked the guest in (by name)');
select pg_temp.check((select (r.check_in_code, r.checked_in_by) = ('W12', pg_temp.fx('staff')) and r.attended_at is not null
                        from pg_temp.gday(pg_temp.fx('g1'), pg_temp.d(0)) r),
  'D1 the check-in is stored with its code and checker');
select (pg_temp.gday(pg_temp.fx('g1'), pg_temp.d(0))).attended_at::text as d1_at \gset

-- Device B (Staff Two) has not refreshed: Check in again, with no code, then with another one.
select pg_temp.try_as('staff2', format($q$select public.event_check_in(%L, %L, true, null)::text$q$,
  pg_temp.fx('g1'), pg_temp.d(0))) as d1_second \gset
select split_part(:'d1_second', chr(9), 2)::jsonb as d1_second_j \gset
select pg_temp.check((:'d1_second_j'::jsonb->>'already_in')::boolean and not (:'d1_second_j'::jsonb->>'changed')::boolean
    and (:'d1_second_j'::jsonb->>'check_in_code') = 'W12' and (:'d1_second_j'::jsonb->>'checked_in_by_name') = 'D415 staff'
    and (:'d1_second_j'::jsonb->>'attended_at')::timestamptz = :'d1_at'::timestamptz,
  'D1 a second Check in answers already_in, with the first one''s time, checker and code');
select pg_temp.try_as('staff2', format($q$select public.event_check_in(%L, %L, true, 'W99')::text$q$, pg_temp.fx('g1'), pg_temp.d(0))) as d1_third \gset
select pg_temp.check((select (r.check_in_code, r.checked_in_by, r.attended_at) = ('W12', pg_temp.fx('staff'), :'d1_at'::timestamptz)
                        from pg_temp.gday(pg_temp.fx('g1'), pg_temp.d(0)) r)
    and pg_temp.audits(pg_temp.fx('g1')) = 'event_checked_in',
  'D1 neither erases nor replaces the first device''s code, time or checker, and neither is audited');

-- Save code: the one way to change a code; an empty one clears it.
select pg_temp.try_as('staff2', format($q$select public.event_check_in(%L, %L, true, 'W13', true)::text$q$, pg_temp.fx('g1'), pg_temp.d(0))) as d1_save \gset
select pg_temp.check(split_part(:'d1_save', chr(9), 1) = 'ok'
    and (select (r.check_in_code, r.checked_in_by, r.attended_at) = ('W13', pg_temp.fx('staff'), :'d1_at'::timestamptz)
           from pg_temp.gday(pg_temp.fx('g1'), pg_temp.d(0)) r),
  'D1 Save code changes the code only: the time and the checker stay');
select pg_temp.as_user('staff2');
select public.event_check_in(pg_temp.fx('g1'), pg_temp.d(0), true, '   ', true);
select pg_temp.check((pg_temp.gday(pg_temp.fx('g1'), pg_temp.d(0))).check_in_code is null
    and (pg_temp.gday(pg_temp.fx('g1'), pg_temp.d(0))).attended_at is not null,
  'D1 Save code with an empty code clears the code and keeps the check-in');
select pg_temp.check(pg_temp.err(format($q$select public.event_check_in(%L, %L, true, 'W1', true)$q$, pg_temp.fx('g2'), pg_temp.d(0)))
    ~ 'is not checked in for .* yet. Check them in first'
    and (pg_temp.gday(pg_temp.fx('g2'), pg_temp.d(0))).attended_at is null,
  'D1 Save code for a guest who is not in is refused (it does not check them in)');
select pg_temp.check(pg_temp.err(format($q$select public.event_check_in(%L, %L, false, 'W1', true)$q$, pg_temp.fx('g1'), pg_temp.d(0)))
    ~ 'saved with a check-in, not with an undo',
  'D1 Save code with an undo is refused');
select pg_temp.check(pg_temp.err(format($q$select public.event_check_in(%L, %L, null)$q$, pg_temp.fx('g1'), pg_temp.d(0)))
    ~ 'Say whether the guest is in', 'D1 a check-in must say in or out');

-- Undo: cleared, and the audit log keeps what it was.
select public.event_check_in(pg_temp.fx('g1'), pg_temp.d(0), true, 'W14', true);
select public.event_check_in(pg_temp.fx('g1'), pg_temp.d(0), false) as d1_undo \gset
select pg_temp.check((select r.attended_at is null and r.checked_in_by is null and r.check_in_code is null
                        from pg_temp.gday(pg_temp.fx('g1'), pg_temp.d(0)) r)
    and (:'d1_undo'::jsonb->>'changed')::boolean and (:'d1_undo'::jsonb->>'checked_in_by_name') is null,
  'D1 Undo clears the time, the checker and the code');
select pg_temp.check(pg_temp.audits(pg_temp.fx('g1')) =
    'event_check_in_code_changed,event_check_in_code_changed,event_check_in_code_changed,event_check_in_undone,event_checked_in',
  'D1 the check-in, each code change (three) and the undo are in the audit log: ' || pg_temp.audits(pg_temp.fx('g1')));
select pg_temp.check((select string_agg(coalesce(a.old_data->>'check_in_code', '-') || '>' || coalesce(a.new_data->>'check_in_code', '-'), ','
                               order by a.old_data->>'check_in_code' nulls first)
                        from public.audit_logs a where a.record_id = pg_temp.fx('g1') and a.action = 'event_check_in_code_changed')
                       = '->W14,W12>W13,W13>-',
  'D1 each code change keeps the code before and after');
select pg_temp.check((select (a.old_data->>'attended_at')::timestamptz = :'d1_at'::timestamptz
                         and (a.old_data->>'checked_in_by')::uuid = pg_temp.fx('staff') and a.old_data->>'check_in_code' = 'W14'
                         and a.new_data->>'attended_at' is null and a.changed_by = pg_temp.fx('staff2')
                         and (a.new_data->>'event_id')::uuid = pg_temp.fx('ev') and (a.new_data->>'day')::date = pg_temp.d(0)
                        from public.audit_logs a where a.record_id = pg_temp.fx('g1') and a.action = 'event_check_in_undone'),
  'D1 the undo''s audit row keeps the time, the checker and the code it cleared, and who undid it');
select public.event_check_in(pg_temp.fx('g1'), pg_temp.d(0), false) as d1_undo2 \gset
select pg_temp.check(not (:'d1_undo2'::jsonb->>'changed')::boolean
    and (select count(*) from public.audit_logs where record_id = pg_temp.fx('g1') and action = 'event_check_in_undone') = 1,
  'D1 undoing a guest who is not in changes nothing and is not audited');
select public.event_check_in(pg_temp.fx('g1'), pg_temp.d(1), true, 'T2');
select pg_temp.check((pg_temp.gday(pg_temp.fx('g1'), pg_temp.d(1))).check_in_code = 'T2'
    and (pg_temp.gday(pg_temp.fx('g1'), pg_temp.d(0))).attended_at is null,
  'D1 each day is checked in by itself');

-- Who gets in: active staff of the event's store; nobody else.
select pg_temp.as_server();
update public.profiles set is_active = false where id = pg_temp.fx('leaver');
select pg_temp.check(split_part(pg_temp.try_as('leaver', format($q$select public.event_check_in(%L, %L, true)::text$q$,
    pg_temp.fx('g2'), pg_temp.d(0))), chr(9), 1) = '42501'
  and split_part(pg_temp.try_as('nostaff', format($q$select public.event_check_in(%L, %L, true)::text$q$,
    pg_temp.fx('g2'), pg_temp.d(0))), chr(9), 1) = '42501'
  and (pg_temp.gday(pg_temp.fx('g2'), pg_temp.d(0))).attended_at is null,
  'D1 a deactivated employee and a login that is not staff are refused (42501) and change nothing');
select pg_temp.check(pg_temp.try_as('owner', 'select 1') like 'ok%'
    and split_part(pg_temp.try_as('nostaff', format($q$select public.event_set_guest_cancelled(%L, true, null)::text$q$, pg_temp.fx('g2'))), chr(9), 1) = '42501',
  'D1 cancelling a guest is refused to a login that is not staff (42501)');

-- ═════ D2 The registrar ═════
select pg_temp.as_user('staff');
do $$ declare r jsonb; begin
  r := public.event_save_guest(jsonb_build_object('event_id', pg_temp.fx('ev'), 'name', 'D415 Guest Three',
         'days', jsonb_build_array(pg_temp.d(1)), 'registered_by', pg_temp.fx('staff2')));
  insert into fx values ('g3', (r->>'guest_id')::uuid);
end $$;
select pg_temp.as_server();
update public.profiles set is_active = false where id = pg_temp.fx('staff2');
select pg_temp.as_user('staff');
select coalesce(pg_temp.err(format($q$select public.event_save_guest(%L::jsonb)$q$, jsonb_build_object('id', pg_temp.fx('g3'),
    'name', 'D415 Guest Three Renamed', 'days', jsonb_build_array(pg_temp.d(1)), 'registered_by', pg_temp.fx('staff2')))), '') as d2_err \gset
select pg_temp.check(:'d2_err' = ''
    and (select (name, registered_by) = ('D415 Guest Three Renamed', pg_temp.fx('staff2')) from public.event_guests where id = pg_temp.fx('g3')),
  'D2 a guest whose registrar has left can still be edited, keeping the registrar: ' || :'d2_err');
select pg_temp.check(pg_temp.err(format($q$select public.event_save_guest(%L::jsonb)$q$, jsonb_build_object('id', pg_temp.fx('g1'),
    'name', 'D415 Guest One', 'days', jsonb_build_array(pg_temp.d(0), pg_temp.d(1)), 'registered_by', pg_temp.fx('staff2'))))
    ~ 'registered the guest was not found',
  'D2 a registrar who has left cannot be given to another guest');
select public.event_save_guest(jsonb_build_object('id', pg_temp.fx('g3'), 'name', 'D415 Guest Three',
  'days', jsonb_build_array(pg_temp.d(1))));
select pg_temp.check((select registered_by from public.event_guests where id = pg_temp.fx('g3')) = pg_temp.fx('staff2'),
  'D2 a save that does not name a registrar keeps the one there');
select public.event_save_guest(jsonb_build_object('id', pg_temp.fx('g3'), 'name', 'D415 Guest Three',
  'days', jsonb_build_array(pg_temp.d(1)), 'registered_by', null));
select pg_temp.check((select registered_by from public.event_guests where id = pg_temp.fx('g3')) is null
    and exists (select 1 from public.audit_logs a where a.record_id = pg_temp.fx('g3') and a.action = 'event_guest_changed'
                 and (a.old_data->>'registered_by')::uuid = pg_temp.fx('staff2') and a.new_data->>'registered_by' is null),
  'D2 Not recorded clears the registrar, and the audit log says so');
select pg_temp.as_server();
update public.profiles set is_active = true where id = pg_temp.fx('staff2');

-- ═════ D3 Cancel and restore ═════
select pg_temp.as_user('staff');
select public.event_check_in(pg_temp.fx('g2'), pg_temp.d(0), true, 'W20');
select pg_temp.check(pg_temp.err(format($q$select public.event_set_guest_cancelled(%L, true, 'not coming')$q$, pg_temp.fx('g2')))
    ~ 'has already checked in. Undo the check-in first'
    and (select status from public.event_guests where id = pg_temp.fx('g2')) = 'registered',
  'D3 a free guest who has checked in is not cancelled');
select public.event_check_in(pg_temp.fx('g2'), pg_temp.d(0), false);
select public.event_set_guest_cancelled(pg_temp.fx('g2'), true, 'D415 not coming') as d3_cancel \gset
select pg_temp.check((:'d3_cancel'::jsonb->>'status') = 'cancelled' and (:'d3_cancel'::jsonb->'over_capacity') = '[]'::jsonb
    and (select status from public.event_guests where id = pg_temp.fx('g2')) = 'cancelled',
  'D3 once the check-in is undone, the guest is cancelled (the answer says so)');
-- Tomorrow is taken off the event while Guest Four, on today and tomorrow, is cancelled.
do $$ declare r jsonb; begin
  r := public.event_save_guest(jsonb_build_object('event_id', pg_temp.fx('ev'), 'name', 'D415 Guest Four',
         'days', jsonb_build_array(pg_temp.d(0), pg_temp.d(1))));
  insert into fx values ('g4', (r->>'guest_id')::uuid);
  r := public.event_save_guest(jsonb_build_object('event_id', pg_temp.fx('ev'), 'name', 'D415 Guest Five',
         'days', jsonb_build_array(pg_temp.d(1))));
  insert into fx values ('g5', (r->>'guest_id')::uuid);
  perform public.event_set_guest_cancelled(pg_temp.fx('g4'), true, null);
  perform public.event_set_guest_cancelled(pg_temp.fx('g5'), true, null);
  perform public.event_set_guest_cancelled(pg_temp.fx('g3'), true, null);
  -- Guest One was checked in tomorrow; undo, then cancel, so tomorrow can go.
  perform public.event_check_in(pg_temp.fx('g1'), pg_temp.d(1), false);
  perform public.event_set_guest_cancelled(pg_temp.fx('g1'), true, null);
end $$;
select pg_temp.as_user('manager');
select public.event_save(public.event_summary(pg_temp.fx('ev')) || jsonb_build_object('store_ids', jsonb_build_array(pg_temp.fx('van')),
  'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(0), 'capacity', 1)),
  'options', (select jsonb_agg(o) from jsonb_array_elements(public.event_summary(pg_temp.fx('ev'))->'options') o where o->>'name' = '1 Day')));
select pg_temp.check((select array_agg(day) from public.event_days where event_id = pg_temp.fx('ev')) = array[pg_temp.d(0)],
  'D3 (set-up) tomorrow is no longer a day of the event, and today holds 1');
select pg_temp.as_user('staff');
select public.event_set_guest_cancelled(pg_temp.fx('g1'), false) as d3_r1 \gset
select pg_temp.check((:'d3_r1'::jsonb->>'status') = 'registered'
    and (:'d3_r1'::jsonb->'days_dropped') = to_jsonb(array[pg_temp.d(1)])
    and (select array_agg(day) from public.event_guest_days where guest_id = pg_temp.fx('g1')) = array[pg_temp.d(0)],
  'D3 a restored guest loses the day the event no longer has, and the answer names it');
select public.event_set_guest_cancelled(pg_temp.fx('g4'), false) as d3_r4 \gset
select pg_temp.check((:'d3_r4'::jsonb->'over_capacity') = jsonb_build_array(jsonb_build_object('day', pg_temp.d(0), 'capacity', 1, 'registered', 2))
    and (select status from public.event_guests where id = pg_temp.fx('g4')) = 'registered',
  'D3 a restore that takes a day over capacity still restores, and warns as adding a guest does (2 of 1)');
select pg_temp.check(pg_temp.err(format('select public.event_set_guest_cancelled(%L, false)', pg_temp.fx('g5')))
    ~ 'None of .* days are still days of this event'
    and (select status from public.event_guests where id = pg_temp.fx('g5')) = 'cancelled'
    and (select count(*) from public.event_guest_days where guest_id = pg_temp.fx('g5')) = 1,
  'D3 a guest none of whose days remain is not restored, and keeps their record');
select public.event_save_guest(jsonb_build_object('id', pg_temp.fx('g1'), 'name', 'D415 Guest One Again',
  'days', jsonb_build_array(pg_temp.d(0))));
select pg_temp.check((select name from public.event_guests where id = pg_temp.fx('g1')) = 'D415 Guest One Again',
  'D3 a restored guest can be edited again');
select pg_temp.check(exists (select 1 from public.audit_logs a where a.record_id = pg_temp.fx('g1') and a.action = 'event_guest_restored'
                              and a.new_data->'days_dropped' = to_jsonb(array[pg_temp.d(1)])),
  'D3 the restore''s audit row names the days dropped');

-- ═════ D4 The editor's locks ═════
select pg_temp.as_user('owner');
do $$ declare v uuid; inv uuid; begin
  -- Two days at the van and the shop; tickets: a live one at the shop, a
  -- deleted one at the van (1 Day, tomorrow).
  v := public.event_save(jsonb_build_object('name', 'D415 Locks ' || pg_temp.tx('sfx'),
    'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(0)), jsonb_build_object('day', pg_temp.d(1)),
                              jsonb_build_object('day', pg_temp.d(2))),
    'store_ids', jsonb_build_array(pg_temp.fx('van'), pg_temp.fx('shop')),
    'options', jsonb_build_array(jsonb_build_object('name', 'Day Pass', 'days_count', 1, 'price', 20, 'sort_order', 1),
                                 jsonb_build_object('name', 'Old Pass', 'days_count', 1, 'price', 10, 'sort_order', 2),
                                 jsonb_build_object('name', 'Spare', 'days_count', 1, 'price', 5, 'sort_order', 3))));
  insert into fx values ('ev4', v);
  insert into fx select 'pass', id from public.event_ticket_options where event_id = v and name = 'Day Pass';
  insert into fx select 'oldpass', id from public.event_ticket_options where event_id = v and name = 'Old Pass';
  insert into fx select 'spare', id from public.event_ticket_options where event_id = v and name = 'Spare';
  inv := pg_temp.sell('shop', jsonb_build_array(pg_temp.ticket('pass', array['D415 Shop Buyer'], array[pg_temp.d(2)])));
  insert into fx values ('inv_shop', inv);
  inv := pg_temp.sell('van', jsonb_build_array(pg_temp.ticket('oldpass', array['D415 Deleted Buyer'], array[pg_temp.d(1)])));
  insert into fx values ('inv_del', inv);
  update public.invoices set deleted_at = now() where id = inv;
end $$;
select invoice_no as inv_shop_no from public.invoices where id = pg_temp.fx('inv_shop') \gset
select invoice_no as inv_del_no from public.invoices where id = pg_temp.fx('inv_del') \gset
select public.event_summary(pg_temp.fx('ev4')) as s4 \gset
select pg_temp.check((select array_agg((x->>'ticket_lines')::int order by x->>'day') from jsonb_array_elements(:'s4'::jsonb->'days') x) = array[0, 0, 1]
    and (select (o->>'sold')::boolean = false and (o->>'on_any_invoice')::boolean from jsonb_array_elements(:'s4'::jsonb->'options') o where o->>'name' = 'Old Pass')
    and (select (o->>'sold')::boolean and (o->>'on_any_invoice')::boolean from jsonb_array_elements(:'s4'::jsonb->'options') o where o->>'name' = 'Day Pass')
    and (select not (o->>'sold')::boolean and not (o->>'on_any_invoice')::boolean from jsonb_array_elements(:'s4'::jsonb->'options') o where o->>'name' = 'Spare'),
  'D4 event_summary: ticket lines per day count live invoices only; sold means a live invoice, on_any_invoice a deleted one too');
-- A deleted invoice no longer holds tomorrow, nor Old Pass's days covered.
select public.event_save(:'s4'::jsonb || jsonb_build_object('store_ids', jsonb_build_array(pg_temp.fx('van'), pg_temp.fx('shop')),
  'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(0)), jsonb_build_object('day', pg_temp.d(2))),
  'options', (select jsonb_agg(case when o->>'name' = 'Old Pass' then o || '{"days_count": 2}' else o end)
                from jsonb_array_elements(:'s4'::jsonb->'options') o)));
select pg_temp.check((select array_agg(day order by day) from public.event_days where event_id = pg_temp.fx('ev4')) = array[pg_temp.d(0), pg_temp.d(2)]
    and (select days_count from public.event_ticket_options where id = pg_temp.fx('oldpass')) = 2,
  'D4 a ticket on a deleted invoice no longer holds a day, nor the days its option covers');
-- But it still holds the option itself, and the refusal names the invoice.
select pg_temp.check(pg_temp.err(format('select public.event_save(%L::jsonb)', public.event_summary(pg_temp.fx('ev4'))
    || jsonb_build_object('store_ids', jsonb_build_array(pg_temp.fx('van'), pg_temp.fx('shop')),
         'options', (select jsonb_agg(o) from jsonb_array_elements(public.event_summary(pg_temp.fx('ev4'))->'options') o where o->>'name' <> 'Old Pass'))))
    = format('"Old Pass" is on %s (deleted), so it cannot be removed. Take it off sale instead.', :'inv_del_no'),
  'D4 an option on a deleted invoice cannot be removed (its line keeps it), and the refusal says which invoice');
-- Taking the day after tomorrow off (every option then covers one day).
create function pg_temp.drop_d2(stores jsonb) returns text language sql as
$$ select coalesce(pg_temp.err(format('select public.event_save(%L::jsonb)', public.event_summary(pg_temp.fx('ev4'))
     || jsonb_build_object('store_ids', stores, 'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(0))),
          'options', (select jsonb_agg(o || '{"days_count": 1}') from jsonb_array_elements(public.event_summary(pg_temp.fx('ev4'))->'options') o)))), '') $$;
select pg_temp.drop_d2(jsonb_build_array(pg_temp.fx('van'), pg_temp.fx('shop'))) as d4_e1 \gset
select pg_temp.check(:'d4_e1' = format('%s cannot be removed: tickets on %s cover it. Correct those invoices first.', to_char(pg_temp.d(2), 'DD Mon YYYY'), :'inv_shop_no'),
  'D4 a live ticket holds its day, and the refusal names its invoice (no longer "People are registered"): ' || :'d4_e1');
-- A Manager of the van only: the shop's invoice is counted, not named.
select pg_temp.as_user('manager');
select pg_temp.drop_d2(jsonb_build_array(pg_temp.fx('van'))) as d4_e2 \gset
select pg_temp.check(:'d4_e2' = format('%s cannot be removed: a ticket on an invoice of another store covers it. Correct those invoices first.', to_char(pg_temp.d(2), 'DD Mon YYYY')),
  'D4 an invoice at a store the person does not work at is counted, not named: ' || :'d4_e2');
select pg_temp.as_user('owner');
do $$ declare r jsonb; begin
  r := public.event_save_guest(jsonb_build_object('event_id', pg_temp.fx('ev4'), 'name', 'D415 Locks Guest', 'days', jsonb_build_array(pg_temp.d(2))));
end $$;
select pg_temp.drop_d2(jsonb_build_array(pg_temp.fx('van'), pg_temp.fx('shop'))) as d4_e3 \gset
select pg_temp.check(:'d4_e3' = format('%s cannot be removed: 1 free guest is registered for it, and tickets on %s cover it. Cancel or move those guests, and correct those invoices, first.',
             to_char(pg_temp.d(2), 'DD Mon YYYY'), :'inv_shop_no'),
  'D4 free guests and tickets on one day are both named (a ticket guest comes with their invoice): ' || :'d4_e3');
-- Whole numbers and cents, refused with words, never a raw database error.
create function pg_temp.save4(patch jsonb, opt_patch jsonb default '{}') returns text language sql as
$$ select pg_temp.err(format('select public.event_save(%L::jsonb)', public.event_summary(pg_temp.fx('ev4'))
     || jsonb_build_object('store_ids', jsonb_build_array(pg_temp.fx('van'), pg_temp.fx('shop')),
          'options', (select jsonb_agg(case when o->>'name' = 'Spare' then o || opt_patch else o end)
                        from jsonb_array_elements(public.event_summary(pg_temp.fx('ev4'))->'options') o))
     || patch)) $$;
select pg_temp.check(pg_temp.save4('{}', '{"sort_order": 1.5}') = 'The order of the "Spare" ticket must be a whole number'
    and pg_temp.save4('{}', '{"sort_order": "x"}') = 'The order of the "Spare" ticket must be a whole number'
    and pg_temp.save4('{}', '{"sort_order": -2}') is null,
  'D4 Order must be a whole number (1.5 is refused in words)');
select coalesce(pg_temp.save4('{}', '{"price": 10.50}'), '') as d4_price_err \gset
select pg_temp.check(pg_temp.save4('{}', '{"price": 10.555}') = 'Prices are in dollars and cents: the "Spare" ticket''s price has more than 2 decimals'
    and pg_temp.save4('{}', '{"price": -1}') = 'The "Spare" ticket needs a price of zero or more'
    and pg_temp.save4('{}', '{"price": "abc"}') = 'The "Spare" ticket needs a price of zero or more'
    and :'d4_price_err' = ''
    and (select price from public.event_ticket_options where id = pg_temp.fx('spare')) = 10.50,
  'D4 a price is in dollars and cents: 10.555 is refused, not rounded');
select pg_temp.check(pg_temp.save4('{}', '{"days_count": 1.5}') ~ 'must cover between 1 and 2 day'
    and pg_temp.save4(jsonb_build_object('days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(0), 'capacity', 2.5),
                                                                   jsonb_build_object('day', pg_temp.d(2)))))
        = 'A day''s capacity must be a whole number more than zero, or left empty for no limit'
    and pg_temp.save4(jsonb_build_object('early_bird_until', pg_temp.d(-1), 'early_bird_percent', 12.345))
        = 'The early-bird discount may have at most 2 decimals'
    and pg_temp.save4(jsonb_build_object('early_bird_until', pg_temp.d(-1), 'early_bird_percent', 12.5)) is null,
  'D4 days covered and capacity are whole numbers, the early-bird percent has at most 2 decimals');

-- ═════ D5 Deleting an event with a website channel ═════
select pg_temp.as_user('owner');
do $$ declare v uuid; begin
  v := public.event_save(jsonb_build_object('name', 'D415 Web ' || pg_temp.tx('sfx'),
    'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(0)), jsonb_build_object('day', pg_temp.d(1))),
    'store_ids', jsonb_build_array(pg_temp.fx('van')),
    'options', jsonb_build_array(jsonb_build_object('name', 'Web Day', 'days_count', 1, 'price', 61))));
  insert into fx values ('ev5', v);
  insert into fx select 'webday', id from public.event_ticket_options where event_id = v;
  insert into public.web_order_channels (key, event_id, ticket_map, store_id, acting_profile_id, payment_method_id,
                                         source_option_id, source_details, mode)
  values (pg_temp.tx('channel'), v, jsonb_build_object(
            'day1', jsonb_build_object('option_id', pg_temp.fx('webday'), 'days', jsonb_build_array(pg_temp.d(0)))),
          pg_temp.fx('van'), pg_temp.fx('owner'), pg_temp.fx('pm'), pg_temp.fx('src'), 'D415 Web (website)', 'live');
end $$;
select public.event_summary(pg_temp.fx('ev5'))->>'web_channel_mode' as d5_mode \gset
select pg_temp.check(:'d5_mode' = 'live' and public.event_summary(pg_temp.fx('ev4'))->'web_channel_mode' = 'null'::jsonb,
  'D5 event_summary says the mode of the event''s website channel (null without one)');
select pg_temp.check(pg_temp.err(format('select public.event_delete(%L, ''D415'')', pg_temp.fx('ev5')))
    = format('The website still takes orders for "D415 Web %s". Switch its channel Off, then delete the event.', pg_temp.tx('sfx')),
  'D5 an event whose website channel is Live is not deleted');
select pg_temp.as_server();
update public.web_order_channels set mode = 'record_only' where key = pg_temp.tx('channel');
do $$ declare r jsonb; begin
  r := public.web_order_paid(pg_temp.paid(pg_temp.sess('A'), 'day1', 1, 6100, 'D415 Web Buyer', pg_temp.phone()));
  insert into tx values ('d5_status', r->>'status');
end $$;
update public.web_order_channels set mode = 'off' where key = pg_temp.tx('channel');
select pg_temp.as_user('owner');
select pg_temp.check(pg_temp.tx('d5_status') = 'recorded'
    and pg_temp.err(format('select public.event_delete(%L, ''D415'')', pg_temp.fx('ev5')))
        = format('The website channel of "D415 Web %s" has 1 order(s) waiting for an invoice. Create or link their invoices first.', pg_temp.tx('sfx')),
  'D5 an event whose channel is Off but holds an order waiting for an invoice is not deleted');

-- ═════ D6 A paid website order for a ticket taken off sale ═════
-- The ticket goes off sale in the app while the order waits.
update public.event_ticket_options set is_active = false where id = pg_temp.fx('webday');
select pg_temp.as_server();
select public.web_order_make_invoice(pg_temp.order_id(pg_temp.sess('A'))) as d6 \gset
select pg_temp.check((:'d6'::jsonb->>'status') = 'invoiced' and (:'d6'::jsonb->>'invoice_no') is not null
    and (select (status, invoice_id is not null) = ('invoiced', true) from public.web_orders where id = pg_temp.order_id(pg_temp.sess('A'))),
  'D6 a paid website order for a ticket taken off sale is still invoiced: ' || :'d6');
select pg_temp.check(coalesce(current_setting('energia.paid_web_order', true), '') = '',
  'D6 the flag that let it pass is cleared after');
select pg_temp.check(exists (select 1 from public.event_guests g join public.web_orders w on w.invoice_id = g.invoice_id
                              where w.id = pg_temp.order_id(pg_temp.sess('A')) and g.status = 'registered'),
  'D6 and its people are on the guest list');
-- A hand invoice for the same ticket is still refused, flag or not.
select pg_temp.as_user('staff');
select pg_temp.check(pg_temp.err(format('select pg_temp.sell(''van'', %L::jsonb)',
    jsonb_build_array(pg_temp.ticket('webday', array['D415 Hand'], array[pg_temp.d(0)])))) ~ 'not on sale',
  'D6 a hand invoice for a ticket off sale is refused');
select set_config('energia.paid_web_order', pg_temp.order_id(pg_temp.sess('A'))::text, true);
select pg_temp.check(pg_temp.err(format('select pg_temp.sell(''van'', %L::jsonb)',
    jsonb_build_array(pg_temp.ticket('webday', array['D415 Hand'], array[pg_temp.d(0)])))) ~ 'not on sale',
  'D6 the flag naming an order already invoiced lets nothing through');
select set_config('energia.paid_web_order', gen_random_uuid()::text, true);
select pg_temp.check(pg_temp.err(format('select pg_temp.sell(''van'', %L::jsonb)',
    jsonb_build_array(pg_temp.ticket('webday', array['D415 Hand'], array[pg_temp.d(0)])))) ~ 'not on sale',
  'D6 the flag naming no order lets nothing through');
select set_config('energia.paid_web_order', '', true);
-- No client role may set it through the API: PostgREST runs public functions only, and none sets it but this one.
select pg_temp.check((select string_agg(p.proname, ',') from pg_proc p
                       where p.pronamespace = 'public'::regnamespace
                         and position('energia.paid_web_order' in pg_get_functiondef(p.oid)) > 0)
                       in ('event_ticket_line_check,web_order_make_invoice', 'web_order_make_invoice,event_ticket_line_check')
    and not has_function_privilege('authenticated', 'public.web_order_make_invoice(uuid,uuid,boolean,boolean)', 'execute')
    and not has_function_privilege('authenticated', 'public.event_ticket_line_check(jsonb,date,uuid,integer)', 'execute'),
  'D6 only web_order_make_invoice sets the flag and only event_ticket_line_check reads it; neither is a client''s');
update public.event_ticket_options set is_active = true where id = pg_temp.fx('webday');

-- ═════ D7 Linking an invoice made by hand ═════
select pg_temp.as_server();
do $$ declare r jsonb; begin
  -- The channel is off: a live payment and a test payment are both refused.
  r := public.web_order_paid(pg_temp.paid(pg_temp.sess('B'), 'day1', 1, 6100, 'D415 Off Buyer', pg_temp.phone()));
  insert into tx values ('d7_live', r->>'status' || '/' || coalesce(r->>'review_reason', ''));
  r := public.web_order_paid(pg_temp.paid('cs_test_D415T' || pg_temp.tx('sfx'), 'day1', 1, 6100, 'D415 Test Buyer', pg_temp.phone()));
  insert into tx values ('d7_test', r->>'status' || '/' || coalesce(r->>'review_reason', ''));
end $$;
select pg_temp.check(pg_temp.tx('d7_live') = 'refused/The website channel is off' and pg_temp.tx('d7_test') = 'refused/The website channel is off',
  'D7 (set-up) while the channel is off, a website payment is refused with that reason');
create function pg_temp.can_link(sess text, patch jsonb default '{}') returns boolean language sql as
$$ select public.web_order_can_link(jsonb_populate_record(w, patch)) from public.web_orders w where w.stripe_session_id = sess $$;
select pg_temp.check(pg_temp.can_link(pg_temp.sess('B'))
    and not pg_temp.can_link('cs_test_D415T' || pg_temp.tx('sfx'))
    and pg_temp.can_link(pg_temp.sess('B'), '{"provider": "door"}')
    and pg_temp.can_link(pg_temp.sess('B'), '{"status": "recorded", "review_reason": null}')
    and pg_temp.can_link(pg_temp.sess('B'), '{"status": "needs_review", "review_reason": "x"}')
    and not pg_temp.can_link(pg_temp.sess('B'), '{"status": "recorded", "livemode": false}')
    and not pg_temp.can_link(pg_temp.sess('B'), '{"review_reason": "A Stripe test payment"}')
    and not pg_temp.can_link(pg_temp.sess('B'), '{"status": "invoiced"}')
    and not pg_temp.can_link(pg_temp.sess('B'), '{"status": "dismissed"}'),
  'D7 only an order that took real money is linked: recorded or waiting, or refused while the channel was off, website or staff link alike');
select pg_temp.as_user('staff');
do $$ declare v uuid; begin
  v := pg_temp.sell('van', jsonb_build_array(pg_temp.ticket('webday', array['D415 Off Buyer'], array[pg_temp.d(0)])));
  insert into fx values ('inv_hand', v);
end $$;
select invoice_no as inv_hand_no from public.invoices where id = pg_temp.fx('inv_hand') \gset
select pg_temp.as_user('manager');
select public.web_order_link_invoice(pg_temp.order_id(pg_temp.sess('B')), :'inv_hand_no') as d7_link \gset
select pg_temp.check((:'d7_link'::jsonb->>'status') = 'invoiced'
    and (select (status, invoice_id) = ('invoiced', pg_temp.fx('inv_hand')) from public.web_orders where id = pg_temp.order_id(pg_temp.sess('B'))),
  'D7 a website payment refused while the channel was off is linked to the invoice made by hand for it');
select pg_temp.check(pg_temp.err(format('select public.web_order_link_invoice(%L, %L)',
    pg_temp.order_id('cs_test_D415T' || pg_temp.tx('sfx')), :'inv_hand_no')) is not null
    and (select status from public.web_orders where stripe_session_id = 'cs_test_D415T' || pg_temp.tx('sfx')) = 'refused',
  'D7 a test payment is never linked to a real invoice');
-- With nothing waiting and the channel off, the event goes (its tickets aside).
select pg_temp.as_user('owner');
select pg_temp.check(pg_temp.err(format('select public.event_delete(%L, ''D415'')', pg_temp.fx('ev5'))) ~ 'are on invoices',
  'D5 with the channel off and nothing waiting, only its tickets on invoices hold it, as before');

-- A later event with no invoices yet, whose channel is off when someone pays
-- on the website anyway. The payment took real money and waits to be linked
-- to an invoice made by hand (D7), so it holds the event as an order waiting
-- for an invoice does. A test payment refused the same way does not.
select pg_temp.as_user('owner');
do $$ declare v uuid; begin
  v := public.event_save(jsonb_build_object('name', 'D415 Future ' || pg_temp.tx('sfx'),
    'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(10)), jsonb_build_object('day', pg_temp.d(11))),
    'store_ids', jsonb_build_array(pg_temp.fx('van')),
    'options', jsonb_build_array(jsonb_build_object('name', 'Future Day', 'days_count', 1, 'price', 61))));
  insert into fx values ('ev5f', v);
  insert into fx select 'futureday', id from public.event_ticket_options where event_id = v;
  insert into tx values ('channel_f', 'd415f-' || lower(pg_temp.tx('sfx')));
  insert into public.web_order_channels (key, event_id, ticket_map, store_id, acting_profile_id, payment_method_id,
                                         source_option_id, source_details, mode)
  values (pg_temp.tx('channel_f'), v, jsonb_build_object(
            'day1', jsonb_build_object('option_id', pg_temp.fx('futureday'), 'days', jsonb_build_array(pg_temp.d(10)))),
          pg_temp.fx('van'), pg_temp.fx('owner'), pg_temp.fx('pm'), pg_temp.fx('src'), 'D415 Future (website)', 'off');
end $$;
select pg_temp.as_server();
do $$ declare r jsonb; begin
  r := public.web_order_paid(jsonb_set(pg_temp.paid(pg_temp.sess('F'), 'day1', 1, 6100, 'D415 Future Buyer', pg_temp.phone()),
                                       '{channel}', to_jsonb(pg_temp.tx('channel_f'))));
  insert into tx values ('d5f_live', r->>'status' || '/' || coalesce(r->>'review_reason', ''));
  r := public.web_order_paid(jsonb_set(pg_temp.paid('cs_test_D415F' || pg_temp.tx('sfx'), 'day1', 1, 6100, 'D415 Future Test', pg_temp.phone()),
                                       '{channel}', to_jsonb(pg_temp.tx('channel_f'))));
  insert into tx values ('d5f_test', r->>'status' || '/' || coalesce(r->>'review_reason', ''));
end $$;
select pg_temp.as_user('owner');
select pg_temp.check(pg_temp.tx('d5f_live') = 'refused/The website channel is off'
    and pg_temp.tx('d5f_test') = 'refused/The website channel is off'
    and pg_temp.err(format('select public.event_delete(%L, ''D415'')', pg_temp.fx('ev5f')))
        = format('The website channel of "D415 Future %s" has 1 order(s) waiting for an invoice. Create or link their invoices first.', pg_temp.tx('sfx'))
    and (select deleted_at is null from public.events where id = pg_temp.fx('ev5f')),
  'D5 a live payment refused while the channel was off holds the event until it is linked (the test one does not count)');
-- Linked to the invoice made by hand for it: nothing waits, and only that
-- invoice's ticket holds the event.
select pg_temp.as_user('staff');
do $$ declare v uuid; begin
  v := pg_temp.sell('van', jsonb_build_array(pg_temp.ticket('futureday', array['D415 Future Buyer'], array[pg_temp.d(10)])));
  insert into fx values ('inv_future', v);
end $$;
select invoice_no as inv_future_no from public.invoices where id = pg_temp.fx('inv_future') \gset
select pg_temp.as_user('manager');
select public.web_order_link_invoice(pg_temp.order_id(pg_temp.sess('F')), :'inv_future_no') as d5f_link \gset
select pg_temp.as_user('owner');
select pg_temp.check((:'d5f_link'::jsonb->>'status') = 'invoiced'
    and pg_temp.err(format('select public.event_delete(%L, ''D415'')', pg_temp.fx('ev5f')))
        = format('Tickets to "D415 Future %s" are on invoices, so it cannot be deleted. Take it off sale instead.', pg_temp.tx('sfx')),
  'D5 once that payment is linked, only the invoice''s tickets hold the event');

-- ═════ D9 Which event a ticket counts under (EVENTS-4, the Owner) ═════
-- A ticket for an event at the van, sold at the shop on the day another event
-- runs there. It counts under the event the ticket is for.
select pg_temp.as_user('owner');
do $$ declare a uuid; b uuid; inv uuid; begin
  a := public.event_save(jsonb_build_object('name', 'D415 Later ' || pg_temp.tx('sfx'),
    'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(3))), 'store_ids', jsonb_build_array(pg_temp.fx('van')),
    'options', jsonb_build_array(jsonb_build_object('name', 'Later Pass', 'days_count', 1, 'price', 15))));
  b := public.event_save(jsonb_build_object('name', 'D415 Today ' || pg_temp.tx('sfx'),
    'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(0))), 'store_ids', jsonb_build_array(pg_temp.fx('shop')),
    'options', jsonb_build_array(jsonb_build_object('name', 'Today Pass', 'days_count', 1, 'price', 15))));
  insert into fx values ('ev_a', a), ('ev_b', b);
  insert into fx select 'later', id from public.event_ticket_options where event_id = a;
  insert into fx select 'todaypass', id from public.event_ticket_options where event_id = b;
  inv := pg_temp.sell('shop', jsonb_build_array(pg_temp.ticket('later', array['D415 Crossover'])));
  insert into fx values ('inv_cross', inv);
  -- The same day and shop: a sale with no ticket, and a ticket for the day's own event.
  insert into products(name, sku, product_type) values ('D415 Tea', 'D415-T-' || pg_temp.tx('sfx'), 'own') returning id into inv;
  insert into fx values ('tea', inv);
  insert into store_inventory(store_id, product_id, current_qty) values (pg_temp.fx('shop'), inv, 50);
  perform public.set_product_prices(pg_temp.fx('shop'), inv, 20, 20, 'available');
  inv := pg_temp.sell('shop', jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('tea'), 'quantity', 1)));
  insert into fx values ('inv_plain', inv);
  inv := pg_temp.sell('shop', jsonb_build_array(pg_temp.ticket('todaypass', array['D415 Today Guest'])));
  insert into fx values ('inv_today', inv);
end $$;
create function pg_temp.member(inv text) returns text language sql as
$$ select coalesce((select e.name || '/' || m.source from public.event_invoice_membership(array[pg_temp.fx(inv)]) m
                      join public.events e on e.id = m.event_id), 'none') $$;
select pg_temp.member('inv_cross') as d9_cross \gset
select pg_temp.check(:'d9_cross' = 'D415 Later ' || pg_temp.tx('sfx') || '/ticket',
  'D9 a ticket sold on another event''s day counts under the event the ticket is for: ' || :'d9_cross');
-- (Two events run at the shop today, Locks and Today: a sale with no ticket
-- goes to one of them; one holding Today's ticket goes to Today, as the day's
-- event whose ticket it holds.)
select pg_temp.check(pg_temp.member('inv_plain') in ('D415 Today ' || pg_temp.tx('sfx') || '/event_day',
                                                     'D415 Locks ' || pg_temp.tx('sfx') || '/event_day')
    and pg_temp.member('inv_today') = 'D415 Today ' || pg_temp.tx('sfx') || '/event_day',
  'D9 a sale with no ticket still goes by its day and store; a ticket for the day''s own event counts under it: '
    || pg_temp.member('inv_plain') || ', ' || pg_temp.member('inv_today'));
select pg_temp.check(exists (select 1 from jsonb_array_elements(public.event_invoices(pg_temp.fx('ev_a'))) x
                              where (x->>'invoice_id')::uuid = pg_temp.fx('inv_cross') and x->>'source' = 'ticket')
    and not exists (select 1 from jsonb_array_elements(public.event_invoices(pg_temp.fx('ev_b'))) x
                     where (x->>'invoice_id')::uuid = pg_temp.fx('inv_cross'))
    and not exists (select 1 from jsonb_array_elements(public.event_invoices(pg_temp.fx('ev4'))) x
                     where (x->>'invoice_id')::uuid = pg_temp.fx('inv_cross'))
    and (select e.event_id from public.invoice_events(array[pg_temp.fx('inv_cross')]) e) = pg_temp.fx('ev_a')
    and (public.invoice_event_guests(pg_temp.fx('inv_cross'))->'event'->>'event_id')::uuid = pg_temp.fx('ev_a'),
  'D9 the Sales tab, the invoice list''s badge and the invoice''s event follow it');
select pg_temp.check((select (x->'sales'->0->>'invoices')::int = 1 and x->'sales'->0->>'store_name' = 'D415 Shop ' || pg_temp.tx('sfx')
                        from jsonb_array_elements(public.report_events(pg_temp.d(3), pg_temp.d(3))) x
                       where (x->>'event_id')::uuid = pg_temp.fx('ev_a')),
  'D9 the Events report counts it under that event, at the store it was sold');
-- Staff marking still decides first, and undoing it goes back to the ticket.
select public.set_invoice_event(pg_temp.fx('inv_cross'), pg_temp.fx('ev_b'), 'D415 marked');
select pg_temp.check(pg_temp.member('inv_cross') = 'D415 Today ' || pg_temp.tx('sfx') || '/staff',
  'D9 staff marking a sale for another event still decides');
select public.clear_invoice_event(pg_temp.fx('inv_cross'));
select pg_temp.check(pg_temp.member('inv_cross') = 'D415 Later ' || pg_temp.tx('sfx') || '/ticket',
  'D9 undoing the mark goes back to the ticket''s event');

-- One invoice holding tickets for two events: the day's own event (MixDay,
-- the only event at the Mix store today) and an older one (Older, at the van
-- later). The day's event takes it, so its own tickets count under it, not
-- under the older event.
select pg_temp.as_server();
do $$ declare st uuid; begin
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  insert into stores(name, code, country_code) values ('D415 Mix ' || pg_temp.tx('sfx'), 'D415M' || pg_temp.tx('sfx'), 'SG') returning id into st;
  insert into fx values ('mix', st);
end $$;
select pg_temp.as_user('owner');
do $$ declare x uuid; y uuid; inv uuid; begin
  x := public.event_save(jsonb_build_object('name', 'D415 Older ' || pg_temp.tx('sfx'),
    'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(5))), 'store_ids', jsonb_build_array(pg_temp.fx('van')),
    'options', jsonb_build_array(jsonb_build_object('name', 'Older Pass', 'days_count', 1, 'price', 15))));
  y := public.event_save(jsonb_build_object('name', 'D415 MixDay ' || pg_temp.tx('sfx'),
    'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(0))), 'store_ids', jsonb_build_array(pg_temp.fx('mix')),
    'options', jsonb_build_array(jsonb_build_object('name', 'Mix Pass', 'days_count', 1, 'price', 15))));
  insert into fx values ('ev_x', x), ('ev_y', y);
  insert into fx select 'olderpass', id from public.event_ticket_options where event_id = x;
  insert into fx select 'mixpass', id from public.event_ticket_options where event_id = y;
  -- Older really is older (one transaction gives every row the same time).
  update public.events set created_at = now() - interval '30 days' where id = x;
  inv := pg_temp.sell('mix', jsonb_build_array(pg_temp.ticket('mixpass', array['D415 Mix A', 'D415 Mix B']),
                                               pg_temp.ticket('olderpass', array['D415 Older Guest'])));
  insert into fx values ('inv_mix', inv);
  inv := pg_temp.sell('mix', jsonb_build_array(pg_temp.ticket('olderpass', array['D415 Older Only'])));
  insert into fx values ('inv_older_only', inv);
end $$;
select pg_temp.check(pg_temp.member('inv_mix') = 'D415 MixDay ' || pg_temp.tx('sfx') || '/event_day'
    and exists (select 1 from jsonb_array_elements(public.event_invoices(pg_temp.fx('ev_y'))) x
                 where (x->>'invoice_id')::uuid = pg_temp.fx('inv_mix'))
    and not exists (select 1 from jsonb_array_elements(public.event_invoices(pg_temp.fx('ev_x'))) x
                     where (x->>'invoice_id')::uuid = pg_temp.fx('inv_mix')),
  'D9 an invoice holding the day''s own ticket and an older event''s counts under the day''s event: ' || pg_temp.member('inv_mix'));
select pg_temp.check(pg_temp.member('inv_older_only') = 'D415 Older ' || pg_temp.tx('sfx') || '/ticket',
  'D9 a ticket for the older event alone, sold on that day there, still counts under the older event');
select pg_temp.check((select x->'sales' from jsonb_array_elements(public.report_events(pg_temp.d(0), pg_temp.d(5))) x
                       where (x->>'event_id')::uuid = pg_temp.fx('ev_y'))
                       = jsonb_build_array(jsonb_build_object('invoices', 1, 'store_id', pg_temp.fx('mix'),
                           'store_name', 'D415 Mix ' || pg_temp.tx('sfx'), 'paid_amount', 0, 'total_amount', 45))
    and (select (x->'sales'->0->>'invoices')::int = 1 and (x->'sales'->0->>'total_amount')::numeric = 15
                and jsonb_array_length(x->'sales') = 1
           from jsonb_array_elements(public.report_events(pg_temp.d(0), pg_temp.d(5))) x
          where (x->>'event_id')::uuid = pg_temp.fx('ev_x')),
  'D9 the Events report counts the mixed invoice under the day''s event (S$45), and only the other one under the older event');

-- Two events run at the shop today (Locks, the older, and Today), and an
-- invoice there holds tickets for Today and for Later (older still, at the
-- van later). The day's event whose ticket it holds takes it: Today.
select pg_temp.as_server();
update public.events set created_at = now() - interval '30 days' where id = pg_temp.fx('ev_a');
update public.events set created_at = now() - interval '20 days' where id = pg_temp.fx('ev4');
select pg_temp.as_user('owner');
do $$ declare inv uuid; begin
  inv := pg_temp.sell('shop', jsonb_build_array(pg_temp.ticket('later', array['D415 Two Events A']),
                                                pg_temp.ticket('todaypass', array['D415 Two Events B'])));
  insert into fx values ('inv_two', inv);
end $$;
select pg_temp.check(pg_temp.member('inv_two') = 'D415 Today ' || pg_temp.tx('sfx') || '/event_day',
  'D9 with two events running there that day, the one whose ticket the invoice holds takes it: ' || pg_temp.member('inv_two'));

-- As built, a whole invoice follows its ticket, products included (the Owner
-- is asked whether only the ticket lines should): a ticket for Later and 3
-- teas, sold at the shop on Today's day, count under Later.
do $$ declare inv uuid; begin
  inv := pg_temp.sell('shop', jsonb_build_array(pg_temp.ticket('later', array['D415 Mixed Buyer']),
                                                jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('tea'), 'quantity', 3)));
  insert into fx values ('inv_lmixed', inv);
end $$;
select pg_temp.check(pg_temp.member('inv_lmixed') = 'D415 Later ' || pg_temp.tx('sfx') || '/ticket'
    and (select total_amount from public.invoices where id = pg_temp.fx('inv_lmixed')) = 75
    and not exists (select 1 from jsonb_array_elements(public.event_invoices(pg_temp.fx('ev_b'))) x
                     where (x->>'invoice_id')::uuid = pg_temp.fx('inv_lmixed'))
    and (select (x->'sales'->0->>'invoices')::int = 2 and (x->'sales'->0->>'total_amount')::numeric = 90
           from jsonb_array_elements(public.report_events(pg_temp.d(0), pg_temp.d(3))) x
          where (x->>'event_id')::uuid = pg_temp.fx('ev_a')),
  'D9 (as built, the Owner is asked) a ticket and products on one invoice: the whole S$75 counts under the ticket''s event');

-- ═════ D10 Closing an order refunded outside the app ═════
-- A later event with no invoices; its channel is off when a real payment
-- comes in. It holds the event (D5) until it is linked, or closed.
select pg_temp.as_user('owner');
do $$ declare v uuid; begin
  v := public.event_save(jsonb_build_object('name', 'D415 Refund ' || pg_temp.tx('sfx'),
    'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(12))), 'store_ids', jsonb_build_array(pg_temp.fx('van')),
    'options', jsonb_build_array(jsonb_build_object('name', 'Refund Day', 'days_count', 1, 'price', 61))));
  insert into fx values ('ev10', v);
  insert into fx select 'refundday', id from public.event_ticket_options where event_id = v;
  insert into tx values ('channel_r', 'd415r-' || lower(pg_temp.tx('sfx')));
  insert into public.web_order_channels (key, event_id, ticket_map, store_id, acting_profile_id, payment_method_id,
                                         source_option_id, source_details, mode)
  values (pg_temp.tx('channel_r'), v, jsonb_build_object(
            'day1', jsonb_build_object('option_id', pg_temp.fx('refundday'), 'days', jsonb_build_array(pg_temp.d(12)))),
          pg_temp.fx('van'), pg_temp.fx('owner'), pg_temp.fx('pm'), pg_temp.fx('src'), 'D415 Refund (website)', 'off');
end $$;
select pg_temp.as_server();
do $$ declare r jsonb; begin
  r := public.web_order_paid(jsonb_set(pg_temp.paid(pg_temp.sess('R'), 'day1', 1, 6100, 'D415 Refund Buyer', pg_temp.phone()),
                                       '{channel}', to_jsonb(pg_temp.tx('channel_r'))));
  insert into tx values ('d10_paid', r->>'status' || '/' || coalesce(r->>'review_reason', ''));
  r := public.web_order_paid(jsonb_set(pg_temp.paid('cs_test_D415R' || pg_temp.tx('sfx'), 'day1', 1, 6100, 'D415 Refund Test', pg_temp.phone()),
                                       '{channel}', to_jsonb(pg_temp.tx('channel_r'))));
end $$;
select count(*) as d10_invoices_before from public.invoices \gset
select pg_temp.as_user('owner');
select pg_temp.check(pg_temp.tx('d10_paid') = 'refused/The website channel is off'
    and pg_temp.err(format('select public.event_delete(%L, ''D415'')', pg_temp.fx('ev10'))) ~ 'has 1 order\(s\) waiting for an invoice',
  'D10 (set-up) a real payment refused while the channel was off holds its event');
create function pg_temp.close_as(who text, sess text, reason text, close boolean default true) returns text language sql as
$$ select pg_temp.try_as(who, format('select public.web_order_close_refunded(%L, %L, %L)::text', pg_temp.order_id(sess), reason, close)) $$;
select pg_temp.close_as('staff', pg_temp.sess('R'), 'Refunded in Stripe') as d10_staff \gset
select pg_temp.check(:'d10_staff' = '42501' || chr(9) || 'Your role cannot do this.'
    and (select status from public.web_orders where id = pg_temp.order_id(pg_temp.sess('R'))) = 'refused',
  'D10 a member of staff cannot close an order: ' || :'d10_staff');
select pg_temp.close_as('admin', pg_temp.sess('R'), 'Refunded in Stripe') as d10_admin \gset
select pg_temp.check(:'d10_admin' = '42501' || chr(9) || 'Your role cannot do this.'
    and (select (status, review_reason) = ('refused', 'The website channel is off')
           from public.web_orders where id = pg_temp.order_id(pg_temp.sess('R'))),
  'D10 nor can an Admin of its store (an Owner or Manager only), and the order is unchanged: ' || :'d10_admin');
select pg_temp.check(split_part(pg_temp.close_as('nostaff', pg_temp.sess('R'), 'Refunded in Stripe'), chr(9), 1) = '42501'
    and split_part(pg_temp.close_as('leaver', pg_temp.sess('R'), 'Refunded in Stripe'), chr(9), 1) = '42501',
  'D10 nor can a login that is not staff, or one deactivated');
select pg_temp.check(pg_temp.close_as('manager', pg_temp.sess('R'), ' ok ') = 'P0001' || chr(9) || 'Give the reason (at least 3 characters)'
    and pg_temp.close_as('manager', pg_temp.sess('R'), null) = 'P0001' || chr(9) || 'Give the reason (at least 3 characters)',
  'D10 a reason of at least 3 characters is required');
select pg_temp.check(pg_temp.close_as('manager', 'cs_test_D415R' || pg_temp.tx('sfx'), 'Refunded in Stripe')
        = 'P0001' || chr(9) || 'Only an order waiting for its invoice, or a payment refused while the channel was off, can be closed'
    and pg_temp.close_as('manager', pg_temp.sess('A'), 'Refunded in Stripe')
        = 'P0001' || chr(9) || 'Only an order waiting for its invoice, or a payment refused while the channel was off, can be closed',
  'D10 a test payment refused while off (it holds nothing) and an invoiced order cannot be closed');
select pg_temp.close_as('manager', pg_temp.sess('R'), '  Refunded in Stripe on the day  ') as d10_close \gset
select pg_temp.check(split_part(:'d10_close', chr(9), 1) = 'ok'
    and (split_part(:'d10_close', chr(9), 2)::jsonb->>'status') = 'dismissed'
    and (select (status, review_reason, invoice_id) is not distinct from ('dismissed', 'Refunded outside the app: Refunded in Stripe on the day', null::uuid)
           from public.web_orders where id = pg_temp.order_id(pg_temp.sess('R'))),
  'D10 a Manager of its store closes it with the reason: ' || :'d10_close');
select pg_temp.check((select a.old_data->>'status' = 'refused' and a.old_data->>'review_reason' = 'The website channel is off'
                         and a.new_data->>'status' = 'dismissed' and a.new_data->>'order_id' = pg_temp.sess('R')
                         and a.reason = 'Refunded in Stripe on the day' and a.changed_by = pg_temp.fx('manager')
                         and a.module = 'events' and a.store_id = pg_temp.fx('van')
                        from public.audit_logs a
                       where a.table_name = 'web_orders' and a.record_id = pg_temp.order_id(pg_temp.sess('R'))
                         and a.action = 'web_order_closed_refunded'),
  'D10 the close is audited: who, why, and the order as it was before and after');
select pg_temp.check((select count(*) from public.invoices) = :d10_invoices_before,
  'D10 no invoice is made or changed');
select pg_temp.check(split_part(pg_temp.close_as('manager', pg_temp.sess('R'), 'Again'), chr(9), 1) = 'P0001',
  'D10 a closed order cannot be closed again');
-- Closed by mistake: reopened, it waits again and holds the event again.
select pg_temp.close_as('staff', pg_temp.sess('R'), 'Not refunded after all', false) as d10_staff_reopen \gset
select pg_temp.close_as('admin', pg_temp.sess('R'), 'Not refunded after all', false) as d10_admin_reopen \gset
select pg_temp.check(split_part(:'d10_staff_reopen', chr(9), 1) = '42501'
    and :'d10_admin_reopen' = '42501' || chr(9) || 'Your role cannot do this.'
    and (select (status, review_reason) = ('dismissed', 'Refunded outside the app: Refunded in Stripe on the day')
           from public.web_orders where id = pg_temp.order_id(pg_temp.sess('R'))),
  'D10 staff and an Admin cannot reopen it, and it stays closed: ' || :'d10_admin_reopen');
select pg_temp.close_as('owner', pg_temp.sess('R'), 'Not refunded after all', false) as d10_reopen \gset
select pg_temp.check(split_part(:'d10_reopen', chr(9), 1) = 'ok'
    and (select (status, review_reason) = ('refused', 'The website channel is off')
           from public.web_orders where id = pg_temp.order_id(pg_temp.sess('R')))
    and exists (select 1 from public.audit_logs a where a.record_id = pg_temp.order_id(pg_temp.sess('R'))
                 and a.action = 'web_order_reopened' and a.reason = 'Not refunded after all' and a.changed_by = pg_temp.fx('owner')
                 and a.old_data->>'status' = 'dismissed' and a.new_data->>'status' = 'refused'
                 and a.new_data->>'review_reason' = 'The website channel is off'),
  'D10 an Owner reopens one closed by mistake; a payment refused while the channel was off is refused again, as it was, audited: ' || :'d10_reopen');
select pg_temp.try_as('manager', format('select public.web_order_resolve(%L)::text', pg_temp.order_id(pg_temp.sess('R')))) as d10_resolve \gset
select pg_temp.check(:'d10_resolve' = 'P0001' || chr(9) || 'A refused order is not invoiced: The website channel is off'
    and pg_temp.can_link(pg_temp.sess('R'))
    and (select status from public.web_orders where id = pg_temp.order_id(pg_temp.sess('R'))) = 'refused',
  'D10 reopened, Create invoice still refuses it (the channel is off); it is still linked to an invoice made by hand: ' || :'d10_resolve');
select pg_temp.check(pg_temp.err(format('select public.event_delete(%L, ''D415'')', pg_temp.fx('ev10'))) ~ 'has 1 order\(s\) waiting for an invoice'
    and split_part(pg_temp.close_as('owner', pg_temp.sess('R'), 'Not closed', false), chr(9), 2) = 'Only an order closed as refunded can be reopened',
  'D10 reopened, it holds the event again; an order not closed cannot be reopened');
-- A staff-link Dismiss is not a close: it is not reopened here.
select pg_temp.as_server();
update public.web_orders set status = 'dismissed', review_reason = 'Refunded outside the app: typed by hand'
 where stripe_session_id = 'cs_test_D415R' || pg_temp.tx('sfx');
select pg_temp.check(split_part(pg_temp.close_as('owner', 'cs_test_D415R' || pg_temp.tx('sfx'), 'Reopen it', false), chr(9), 2)
    = 'Only an order closed as refunded can be reopened',
  'D10 only an order this closed can be reopened (its audit row says so)');
-- A website order that was waiting for its invoice (sent while the channel
-- took orders) is reopened into Needs review.
select pg_temp.as_server();
update public.web_order_channels set mode = 'record_only' where key = pg_temp.tx('channel_r');
do $$ declare r jsonb; begin
  r := public.web_order_paid(jsonb_set(pg_temp.paid(pg_temp.sess('N'), 'day1', 1, 6100, 'D415 Waiting Buyer', pg_temp.phone()),
                                       '{channel}', to_jsonb(pg_temp.tx('channel_r'))));
  insert into tx values ('d10_n', r->>'status');
end $$;
update public.web_order_channels set mode = 'off' where key = pg_temp.tx('channel_r');
select pg_temp.close_as('owner', pg_temp.sess('N'), 'Refunded in Stripe') as d10_n_close \gset
select pg_temp.close_as('owner', pg_temp.sess('N'), 'Closed by mistake', false) as d10_n_reopen \gset
select pg_temp.check(pg_temp.tx('d10_n') in ('recorded', 'needs_review')
    and split_part(:'d10_n_close', chr(9), 1) = 'ok'
    and (select (status, review_reason) = ('needs_review', 'Reopened after it was closed as refunded. Check the payment, then create or link its invoice.')
           from public.web_orders where id = pg_temp.order_id(pg_temp.sess('N'))),
  'D10 an order that was waiting for its invoice is reopened into Needs review: ' || :'d10_n_reopen');
select pg_temp.close_as('owner', pg_temp.sess('N'), 'Refunded in Stripe, checked') as d10_n_close2 \gset

-- Staff-link registrations. One sent while the channel was off is closed as
-- refunded: the staff link's Restore does not bring it back (Reopen does).
create function pg_temp.door(tag text, cents int) returns jsonb language sql as
$$ select public.web_order_door(jsonb_build_object('channel', pg_temp.tx('channel_r'),
     'order_id', 'OFF-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || upper(substr(md5(pg_temp.tx('sfx') || tag), 1, 6)),
     'ticket', 'day1', 'quantity', 1, 'amount_total_cents', cents, 'paid_on', public.sg_today()::text, 'method', 'cash',
     'registered_at', now(), 'buyer', jsonb_build_object('first_name', 'D415 Door', 'last_name', tag),
     'attendees', jsonb_build_array(jsonb_build_object('name', 'D415 Door ' || tag)))) $$;
create function pg_temp.door_id(tag text) returns uuid language sql as
$$ select pg_temp.order_id('OFF-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || upper(substr(md5(pg_temp.tx('sfx') || tag), 1, 6))) $$;
create function pg_temp.dismiss_as(who text, tag text, reason text, dismiss boolean default true) returns text language sql as
$$ select pg_temp.try_as(who, format('select public.web_order_dismiss(%L, %L, %L)::text', pg_temp.door_id(tag), reason, dismiss)) $$;
select pg_temp.as_server();
select pg_temp.door('D1', 6100)::text as d10_d1 \gset
select pg_temp.try_as('owner', format('select public.web_order_close_refunded(%L, %L)::text', pg_temp.door_id('D1'), 'Refunded by PayNow')) as d10_d1_close \gset
select pg_temp.dismiss_as('owner', 'D1', 'Restore it', false) as d10_d1_owner_restore \gset
select pg_temp.dismiss_as('admin', 'D1', null, false) as d10_d1_admin_restore \gset
select pg_temp.check((:'d10_d1'::jsonb->>'review_reason') = 'The website channel is off'
    and split_part(:'d10_d1_close', chr(9), 1) = 'ok'
    and :'d10_d1_owner_restore' = 'P0001' || chr(9) || 'This order was closed as refunded. Use Reopen instead.'
    and :'d10_d1_admin_restore' = 'P0001' || chr(9) || 'This order was closed as refunded. Use Reopen instead.'
    and (select (status, review_reason) = ('dismissed', 'Refunded outside the app: Refunded by PayNow')
           from public.web_orders where id = pg_temp.door_id('D1'))
    and not exists (select 1 from public.audit_logs a where a.record_id = pg_temp.door_id('D1') and a.action = 'web_order_restored'),
  'D10 a staff-link registration closed as refunded is not restored by Restore, for the Owner or an Admin; it stays closed: ' || :'d10_d1_admin_restore');
select pg_temp.try_as('owner', format('select public.web_order_close_refunded(%L, %L, false)::text', pg_temp.door_id('D1'), 'Closed by mistake')) as d10_d1_reopen \gset
select pg_temp.check(split_part(:'d10_d1_reopen', chr(9), 1) = 'ok'
    and (select (status, review_reason) = ('refused', 'The website channel is off') from public.web_orders where id = pg_temp.door_id('D1')),
  'D10 Reopen puts it back refused, as it was before the close: ' || :'d10_d1_reopen');
select pg_temp.try_as('owner', format('select public.web_order_close_refunded(%L, %L)::text', pg_temp.door_id('D1'), 'Refunded by PayNow, checked')) as d10_d1_close2 \gset

-- One sent while the channel took orders, paid S$50 for a S$61 pass, so it
-- waits in Needs review. A Dismiss reason may not start as a close's does.
-- Closed and reopened, it gets the staff link's checks again. Dismissed
-- after that, Restore still works.
select pg_temp.as_server();
update public.web_order_channels set mode = 'record_only' where key = pg_temp.tx('channel_r');
select pg_temp.door('D2', 5000)::text as d10_d2 \gset
update public.web_order_channels set mode = 'off' where key = pg_temp.tx('channel_r');
select pg_temp.dismiss_as('manager', 'D2', 'Refunded outside the app: paid twice') as d10_d2_prefix \gset
select pg_temp.check((:'d10_d2'::jsonb->>'status') = 'needs_review'
    and :'d10_d2_prefix' = 'P0001' || chr(9) || 'Start the reason another way. "Refunded outside the app:" marks an order closed as refunded.'
    and (select status from public.web_orders where id = pg_temp.door_id('D2')) = 'needs_review',
  'D10 a Dismiss whose reason starts like a close''s is refused, so a dismissed registration is never taken for a closed one: ' || :'d10_d2_prefix');
select pg_temp.try_as('manager', format('select public.web_order_close_refunded(%L, %L)::text', pg_temp.door_id('D2'), 'Refunded in cash')) as d10_d2_close \gset
select pg_temp.try_as('owner', format('select public.web_order_close_refunded(%L, %L, false)::text', pg_temp.door_id('D2'), 'Closed by mistake')) as d10_d2_reopen \gset
select pg_temp.check(split_part(:'d10_d2_close', chr(9), 1) = 'ok'
    and (select status = 'needs_review'
                and review_reason like 'Reopened after it was closed as refunded. Check the payment, then create or link its invoice. S$50.00 was paid, but 1 × "Refund Day" paid on % costs S$61.00.'
           from public.web_orders where id = pg_temp.door_id('D2')),
  'D10 a staff-link registration reopened waits in Needs review with the staff link''s checks: ' || :'d10_d2_reopen');
select pg_temp.dismiss_as('manager', 'D2', 'Duplicate registration') as d10_d2_dismiss \gset
select pg_temp.dismiss_as('admin', 'D2', null, false) as d10_d2_restore \gset
select pg_temp.check(split_part(:'d10_d2_dismiss', chr(9), 1) = 'ok'
    and split_part(:'d10_d2_restore', chr(9), 1) = 'ok'
    and (select (status, review_reason) = ('needs_review', 'S$50.00 was paid, but 1 × "Refund Day" paid on ' || to_char(public.sg_today(), 'DD Mon YYYY') || ' costs S$61.00')
           from public.web_orders where id = pg_temp.door_id('D2')),
  'D10 closed, reopened and then dismissed as usual, it is restored as usual: ' || :'d10_d2_restore');
select pg_temp.dismiss_as('manager', 'D2', 'Test registration') as d10_d2_dismiss2 \gset

-- Closed again, the event can be deleted; then it is not reopened.
select pg_temp.close_as('owner', pg_temp.sess('R'), 'Refunded in Stripe, checked') as d10_close2 \gset
select pg_temp.as_user('owner');
select coalesce(pg_temp.err(format('select public.event_delete(%L, ''D415 refunded'')', pg_temp.fx('ev10'))), '') as d10_delete \gset
select pg_temp.check(split_part(:'d10_close2', chr(9), 1) = 'ok' and :'d10_delete' = ''
    and (select deleted_at is not null from public.events where id = pg_temp.fx('ev10')),
  'D10 with the order closed as refunded, its event is deleted: ' || :'d10_close2' || ' ' || :'d10_delete');
select pg_temp.check(split_part(pg_temp.close_as('owner', pg_temp.sess('R'), 'Reopen it', false), chr(9), 2)
    = 'Its event has been deleted, so the order cannot be reopened',
  'D10 an order of a deleted event is not reopened');
-- Another store's Manager: refused.
select pg_temp.as_server();
update public.web_order_channels set store_id = pg_temp.fx('shop') where key = pg_temp.tx('channel_r');
-- (Deleting it also took its tickets off sale; both are put back here.)
update public.events set deleted_at = null, is_active = true where id = pg_temp.fx('ev10');
select pg_temp.check(pg_temp.close_as('manager', pg_temp.sess('R'), 'Reopen it', false)
    = '42501' || chr(9) || 'That belongs to a store you are not assigned to.',
  'D10 a Manager of another store cannot close or reopen its orders');
-- The website's sync lists it dismissed; a payment sent again answers dismissed.
select public.web_order_sync(pg_temp.tx('channel_r')) as d10_sync \gset
select public.web_order_paid(jsonb_set(pg_temp.paid(pg_temp.sess('R'), 'day1', 1, 6100, 'D415 Refund Buyer', pg_temp.phone()),
                                       '{channel}', to_jsonb(pg_temp.tx('channel_r')))) as d10_again \gset
select pg_temp.check((select o->>'status' from jsonb_array_elements(:'d10_sync'::jsonb->'orders') o where o->>'order_id' = pg_temp.sess('R')) = 'dismissed'
    and (:'d10_again'::jsonb->>'status') = 'dismissed',
  'D10 the website''s sync lists it as dismissed, and a payment sent again answers dismissed');

-- ═════ D11 The website follows On sale ═════
select pg_temp.as_server();
create function pg_temp.passes(chan text) returns jsonb language sql as $$ select public.web_order_tickets(chan) $$;
select pg_temp.check(pg_temp.passes(pg_temp.tx('channel_f')) = '{"status": "ok", "tickets": {"day1": true}}'::jsonb,
  'D11 a pass whose ticket is on sale is on sale for the website: ' || pg_temp.passes(pg_temp.tx('channel_f'))::text);
update public.event_ticket_options set is_active = false where id = pg_temp.fx('futureday');
select pg_temp.check(pg_temp.passes(pg_temp.tx('channel_f'))->'tickets' = '{"day1": false}'::jsonb,
  'D11 taking the ticket off sale closes the pass');
update public.event_ticket_options set is_active = true where id = pg_temp.fx('futureday');
select pg_temp.check(pg_temp.passes(pg_temp.tx('channel_f'))->'tickets' = '{"day1": true}'::jsonb,
  'D11 ticking it back opens it again');
update public.events set is_active = false where id = pg_temp.fx('ev5f');
select pg_temp.check(pg_temp.passes(pg_temp.tx('channel_f'))->'tickets' = '{"day1": false}'::jsonb,
  'D11 the event''s Tickets on sale unticked closes every pass');
update public.events set is_active = true where id = pg_temp.fx('ev5f');
update public.web_order_channels
   set ticket_map = ticket_map || jsonb_build_object('both', jsonb_build_object('option_id', pg_temp.fx('later')),
                                                     'day2', jsonb_build_object('option_id', 'not-a-uuid'), 'day3', '"x"'::jsonb)
 where key = pg_temp.tx('channel_f');
select pg_temp.check(pg_temp.passes(pg_temp.tx('channel_f'))->'tickets' = '{"day1": true, "both": false, "day2": false, "day3": false}'::jsonb
    and pg_temp.passes('d415-no-such-channel') = '{"status": "refused", "tickets": {}}'::jsonb,
  'D11 a pass whose ticket is another event''s, or no ticket, is not on sale; an unknown channel is refused');
select pg_temp.check(pg_temp.passes(pg_temp.tx('channel_r'))->'tickets' = '{"day1": true}'::jsonb,
  'D11 (the Refund event, restored above, sells again)');
update public.events set deleted_at = now() where id = pg_temp.fx('ev10');
select pg_temp.check(pg_temp.passes(pg_temp.tx('channel_r'))->'tickets' = '{"day1": false}'::jsonb,
  'D11 a deleted event sells nothing');
select pg_temp.check(not has_function_privilege('authenticated', 'public.web_order_tickets(text)', 'execute')
    and not has_function_privilege('anon', 'public.web_order_tickets(text)', 'execute')
    and has_function_privilege('service_role', 'public.web_order_tickets(text)', 'execute')
    and split_part(pg_temp.try_as('owner', format('select public.web_order_tickets(%L)::text', pg_temp.tx('channel_f'))), chr(9), 1) = '42501',
  'D11 web_order_tickets is the service role''s alone (the edge function asks it)');

-- ═════ D8 Again, and the grants ═════
select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) as fp_before
  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' \gset
\ir ../../../supabase/415_events_check_in_and_web_orders.sql
select pg_temp.check((select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text))
                        from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f') = :'fp_before',
  'D8 415 run again changes no function');
select pg_temp.check(to_regprocedure('public.event_check_in(uuid,date,boolean,text)') is null
    and (select count(*) from pg_proc where proname in ('event_check_in', 'event_set_guest_cancelled')
           and pronamespace = 'public'::regnamespace) = 2
    and (select prorettype = 'jsonb'::regtype from pg_proc where oid = 'public.event_set_guest_cancelled(uuid,boolean,text)'::regprocedure),
  'D8 one event_check_in (five arguments) and one event_set_guest_cancelled (answering jsonb)');
select pg_temp.check((select bool_and(has_function_privilege('authenticated', f, 'execute') and has_function_privilege('service_role', f, 'execute')
                              and not has_function_privilege('anon', f, 'execute')
                              and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = f and a.grantee = 0))
    from unnest(array['public.event_check_in(uuid,date,boolean,text,boolean)'::regprocedure,
                      'public.event_set_guest_cancelled(uuid,boolean,text)'::regprocedure,
                      'public.event_save_guest(jsonb)'::regprocedure, 'public.event_save(jsonb)'::regprocedure,
                      'public.event_delete(uuid,text)'::regprocedure,
                      'public.web_order_close_refunded(uuid,text,boolean)'::regprocedure,
                      'public.web_order_dismiss(uuid,text,boolean)'::regprocedure]) f),
  'D8 the page''s functions (and the staff link''s Dismiss): authenticated and the service role only');
select pg_temp.check((select bool_and(not has_function_privilege('authenticated', f, 'execute') and not has_function_privilege('anon', f, 'execute')
                              and has_function_privilege('service_role', f, 'execute'))
    from unnest(array['public.event_ticket_line_check(jsonb,date,uuid,integer)'::regprocedure, 'public.event_summary(uuid)'::regprocedure,
                      'public.web_order_can_link(web_orders)'::regprocedure,
                      'public.web_order_make_invoice(uuid,uuid,boolean,boolean)'::regprocedure,
                      'public.event_invoice_membership(uuid[])'::regprocedure, 'public.web_order_tickets(text)'::regprocedure]) f),
  'D8 the internal ones: the service role only');
select pg_temp.check(position('perform public.require_active_staff();' in pg_get_functiondef('public.event_check_in(uuid,date,boolean,text,boolean)'::regprocedure)) > 0
    and position('perform public.require_active_staff();' in pg_get_functiondef('public.event_set_guest_cancelled(uuid,boolean,text)'::regprocedure)) > 0
    and position('begin
  perform public.require_active_staff(''{owner,manager}'');' in pg_get_functiondef('public.web_order_close_refunded(uuid,text,boolean)'::regprocedure)) > 0,
  'D8 the two functions made again, and the close, start by checking the caller is active staff');

do $$ declare v_n int; v_m text; begin
  select count(*), string_agg(f.msg, '; ' order by f.n) into v_n, v_m from failed f;
  if v_n > 0 then raise exception '% check(s) failed: %', v_n, v_m; end if;
  raise notice 'All 415 door checks passed.';
end $$;
rollback;
