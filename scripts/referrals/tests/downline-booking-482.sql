-- A grey "Came in" for someone who has come in without a cal.com booking, on the Downline and on the affiliate
-- portal's My Network (482).
--
-- The Owner, 30 Oct 2026: someone who has ALREADY COME IN but has NO cal.com booking reads a grey word with no date
-- (the state 'visited', which the pages word "Came in": the Owner, 31 Oct 2026) in the Booking column instead of
-- the red "No booking", on both screens and both tiers; "No booking" stays for people who have never come in.
-- "Has come in" is the evidence 480's 'came' uses, on any Singapore day up to and including today: a visit day by
-- THE visit rule (customer_centre_visit_days), or a settled invoice at the Adelphi centre (the store in use coded
-- RETAIL-ADELPHI; not the Van & RoadShow; not deleted; paid, partially paid, FOC, refund requested or refunded; its
-- business date, else the Singapore date it was made; not an online or event order). A booking's state (upcoming,
-- came, miss) does not change; nor do Visited and First visit.
--
--   V  'visited' or 'none' (no booking): a visit only (an older one, one today), and a visit dated after today (none
--      until that day); an Adelphi invoice of each counted status; every other status (each label of
--      invoice_status not counted, read from the catalogue), a deleted invoice, the Van & RoadShow, another
--      store, and an Adelphi invoice that is an online (web) order, a VIP order or an event guest's: none; the
--      Adelphi centre is the store IN USE coded RETAIL-ADELPHI (with it deleted, or its code changed, after 482
--      is in, its purchases stop counting; a visit still counts); the business date, else the Singapore date it
--      was made (made 12.30 am the next day, though that is today in UTC: none; dated yesterday though made
--      later: visited); dated after today: none (visited from that day); nothing at all: none; the state rule
--      with a given day; one row per customer in use asked about.
--   K  A booking keeps its state: upcoming (with earlier visits and purchases), came, miss (with a visit and a
--      purchase on other days, before and after it); only cancelled or rescheduled-away bookings are no booking:
--      visited when they came in, else none.
--   M  Merges: a merged record's booking still follows the merge (the kept record shows it, not 'visited'); the
--      merged record's visit or Adelphi invoice, moved to the kept record by the merge, makes it visited.
--   R  Both screens, both tiers: the staff Downline (as a Manager; Staff and the Owner get the same answer) and the
--      affiliate's My Network answer 'visited' (and no booking_at) for such rows and the state rule's state for
--      every row; Visited and First visit are as they were (a purchase is not a visit); every key as before;
--      where this file installs 482, every row is word for word what it was before but 'none' -> 'visited' for
--      those who came in, and the Downline's rows in the same order.
--   P  The state rule is still the service role's alone; the two screens' grants as before.
--   G  The md5s (482's AFTER; the two screens and the other cal.com functions still 480's) and the grants.
--   N  482 twice changes nothing; its first run changes this one function only, leaves no row and moves no
--      sequence; it refuses (nothing changed) a state rule changed since, a database without 480's migration
--      row, a renamed or deleted Adelphi store, a changed visit rule or Downline function, a grant added; and
--      480's file refuses to run over 482.
--
-- Disposable local database only (a copy of production as it is: run it where 480 is in and 482 is not, and it
-- installs 482 twice, or with -v skip_install=1 where 482 is in; 484, on hold, is not covered here: its checks
-- come with it); everything is rolled back. A copy without
-- production's stores gets made-up RETAIL-ADELPHI and ADELPHI-VAN stores for the run, and a copy built with psql
-- (no migration rows past 478) gets 480's row in supabase_migrations.schema_migrations as production has it, for
-- the run. Every name and email is invented (@example.invalid); phones are ACMA's fictional range
-- (+61 2 5550 ....), found free at run time. Every check runs, then the file fails if any did.
--   psql -X -v ON_ERROR_STOP=1 [-v skip_install=1] -f scripts/referrals/tests/downline-booking-482.sql
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
create function pg_temp.seqs() returns jsonb language sql as
$$ select coalesce(jsonb_object_agg(s.schemaname || '.' || s.sequencename, s.last_value), '{}'::jsonb)
     from pg_sequences s where s.schemaname in ('public', 'auth') $$;
-- md5 of each public function's definition, read with public alone on the search path.
create function pg_temp.fn_md5s() returns table(fn text, md5 text) language sql set search_path = public as
$$ select p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid))
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' $$;
create function pg_temp.md5_of(sig text) returns text language sql set search_path = public as
$$ select md5(pg_get_functiondef(to_regprocedure('public.' || sig))) $$;
set local lock_timeout = '10s';
set local statement_timeout = '600s';
create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create temp table fx(k text primary key, v uuid);
create temp table tx(k text primary key, v text);
grant all on fx, tx to authenticated, anon, service_role;
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
create function pg_temp.tx(key text) returns text language sql as $$ select v from tx where k = key $$;
create function pg_temp.put(key text, val text) returns void language sql as
$$ insert into tx values (key, val) on conflict (k) do update set v = excluded.v $$;
create function pg_temp.putx(key text, val uuid) returns void language sql as
$$ insert into fx values (key, val) on conflict (k) do update set v = excluded.v $$;
-- Run q as a login (a fixture key), 'anon' (signed out), 'service' (the service role) or 'server' (no request at
-- all), through the API's own database role, as the pages do: 'ok', a tab and the answer, or the SQLSTATE, a tab
-- and the message.
create function pg_temp.try_as(who text, q text) returns text language plpgsql as
$$declare v_out text; v_state text; v_msg text;
begin
  begin
    if who = 'server' then
      perform set_config('request.jwt.claims', '', true);
      perform set_config('request.jwt.claim.sub', '', true);
      perform set_config('request.jwt.claim.role', '', true);
    elsif who = 'anon' then
      perform set_config('request.jwt.claims', '{"role":"anon"}', true);
      perform set_config('request.jwt.claim.sub', '', true);
      perform set_config('request.jwt.claim.role', '', true);
      execute 'set local role anon';
    elsif who = 'service' then
      perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
      perform set_config('request.jwt.claim.sub', '', true);
      perform set_config('request.jwt.claim.role', '', true);
      execute 'set local role service_role';
    else
      perform set_config('request.jwt.claims', json_build_object('sub', pg_temp.fx(who), 'role', 'authenticated')::text, true);
      perform set_config('request.jwt.claim.sub', '', true);
      perform set_config('request.jwt.claim.role', '', true);
      execute 'set local role authenticated';
    end if;
    execute q into v_out;
    execute 'reset role';
    perform set_config('request.jwt.claims', '', true);
    return 'ok' || chr(9) || coalesce(v_out, '');
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    perform set_config('request.jwt.claims', '', true);
    return v_state || chr(9) || v_msg;
  end;
end$$;
create function pg_temp.state(v text) returns text language sql as $$ select split_part(v, chr(9), 1) $$;
create function pg_temp.body(v text) returns text language sql as $$ select substr(v, position(chr(9) in v) + 1) $$;
create function pg_temp.mail(tag text) returns text language sql as
$$ select 'cb482-' || lower(tag) || '-' || pg_temp.tx('sfx') || '@example.invalid' $$;
create function pg_temp.ph(n int) returns text language sql as
$$ select '+6125550' || lpad((pg_temp.tx('phbase')::int + n)::text, 4, '0') $$;
-- A moment as cal.com writes it (UTC, milliseconds, Z), and a Singapore day and time as a moment.
create function pg_temp.iso(t timestamptz) returns text language sql as
$$ select to_char(t at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') $$;
create function pg_temp.sg(d date, t time) returns timestamptz language sql as $$ select (d + t) at time zone 'Asia/Singapore' $$;
create function pg_temp.today() returns date language sql as $$ select (now() at time zone 'Asia/Singapore')::date $$;
create function pg_temp.uid(tag text) returns text language sql as $$ select 'cb482' || pg_temp.tx('sfx') || tag $$;
-- A cal.com webhook event for one booking (created, or cancelled), with the WhatsApp-Number answer.
create function pg_temp.book(tag text, start timestamptz, phone text, trig text default 'BOOKING_CREATED',
                             at timestamptz default now() - interval '20 days') returns text language sql as
$$ select public.calcom_booking_ingest(jsonb_build_object('triggerEvent', trig, 'createdAt', pg_temp.iso(at),
     'payload', jsonb_build_object('uid', pg_temp.uid(tag), 'startTime', pg_temp.iso(start), 'endTime', pg_temp.iso(start + interval '1 hour'),
                                   'responses', jsonb_build_object('WhatsApp-Number', jsonb_build_object('label', 'WhatsApp Number', 'value', phone))))) ->> 'result' $$;
-- A visit by the visit rule: a consultant's survey with an answer, dated the Singapore day it was made.
create function pg_temp.visit(key text, at timestamptz) returns void language sql as
$$ insert into public.health_surveys (survey_no, customer_id, full_name, phone, source, submitted_at, remarks_condition)
   values ('HS-T482-' || pg_temp.tx('sfx') || '-' || key || '-' || to_char(at at time zone 'UTC', 'YYYYMMDDHH24MI'), pg_temp.fx(key),
           'T482 ' || key, '+61255500000', 'consultant', at, 'T482 answer') $$;
-- An invoice of the customer's (made by the Owner): store key ('adelphi', 'van', 'other'), status, business date
-- (or none), when it was made, deleted or not.
create function pg_temp.inv(key text, store text, st text, bd date, made timestamptz, del boolean default false) returns uuid language sql as
$$ insert into public.invoices (invoice_no, store_id, customer_id, created_by, status, subtotal, total_amount, paid_amount,
                                business_date, created_at, deleted_at, notes)
   values ('T482-' || pg_temp.tx('sfx') || '-' || key || '-' || st, pg_temp.fx(store), pg_temp.fx(key), pg_temp.fx('owner'),
           st::public.invoice_status, 100, 100, case st when 'paid' then 100 when 'partially_paid' then 40 else 0 end,
           bd, made, case when del then now() end, 'T482 fixture')
   returning id $$;
-- One customer's state (and booking moment) by the state rule (p_today: a given Singapore day, or today).
create function pg_temp.st(key text, d date default null) returns text language sql as
$$ select b.booking_state || coalesce(' ' || pg_temp.iso(b.booking_at), '')
     from public.calcom_customer_bookings(array[pg_temp.fx(key)], d) b $$;
create function pg_temp.st0(key text, d date default null) returns text language sql as
$$ select b.booking_state from public.calcom_customer_bookings(array[pg_temp.fx(key)], d) b $$;
create function pg_temp.states(keys text[], d date default null) returns text language sql as
$$ select string_agg(k || '=' || coalesce(pg_temp.st0(k, d), '?'), ' ' order by o) from unnest(keys) with ordinality x(k, o) $$;
-- A row of a downline or a portal answer, by name: its booking state and moment.
create function pg_temp.rows_by(j jsonb, tier text, namekey text) returns jsonb language sql as
$$ select coalesce(jsonb_object_agg(r ->> namekey, jsonb_build_array(r ->> 'booking_state', r -> 'booking_at')), '{}'::jsonb)
     from jsonb_array_elements(j -> tier) r $$;

-- ═════ Fixture: logins, the stores, a referrer with a portal login and their network (as the server) ═════
set local client_min_messages = warning;
do $$
declare k text; v uuid; st uuid; r uuid; aff uuid; g int; gone text[]; x record; n int := 0;
begin
  perform set_config('request.jwt.claims', '', true);
  -- Letters only, so no run of digits in a uid or an id can be read as a phone number.
  perform pg_temp.put('sfx', translate(lower(substr(md5(gen_random_uuid()::text), 1, 8)), '0123456789', 'ghijklmnop'));
  -- Two hundred free fictional phones in a row (+61 2 5550 nnnn): no customer's, in use (a range scan of the partial
  -- phone index) or deleted (a merged record's booking follows the merge), and no active booking's.
  gone := array(select public.normalize_customer_phone(c.phone) from public.customers c where c.deleted_at is not null);
  for g in 1000 .. 9600 by 200 loop
    continue when exists (select 1 from public.customers c
                           where c.deleted_at is null and public.normalize_customer_phone(c.phone)
                                 between '+6125550' || lpad(g::text, 4, '0') and '+6125550' || lpad((g + 199)::text, 4, '0'));
    continue when exists (select 1 from unnest(gone) y(ph)
                           where y.ph between '+6125550' || lpad(g::text, 4, '0') and '+6125550' || lpad((g + 199)::text, 4, '0'));
    continue when exists (select 1 from public.calcom_bookings b
                           where b.status = 'active'
                             and b.phone_key between '+6125550' || lpad(g::text, 4, '0') and '+6125550' || lpad((g + 199)::text, 4, '0'));
    perform pg_temp.put('phbase', g::text);
    exit;
  end loop;
  if pg_temp.tx('phbase') is null then raise exception 'no free fictional phones'; end if;
  foreach k in array array['owner', 'manager', 'staff', 'aff'] loop
    insert into auth.users (id, email) values (gen_random_uuid(), pg_temp.mail(k)) returning id into v;
    perform pg_temp.putx(k, v);
  end loop;
  insert into public.profiles (id, full_name, email, role, is_active, invitation_status)
  select pg_temp.fx(y.k), 'Test ' || y.k, pg_temp.mail(y.k), y.role::public.user_role, true, 'accepted'
    from (values ('owner', 'owner'), ('manager', 'manager'), ('staff', 'staff')) y(k, role);
  insert into public.stores (name, code, country_code) values ('Test Store 482 ' || pg_temp.tx('sfx'), 'T482' || pg_temp.tx('sfx'), 'SG')
    returning id into st;
  perform pg_temp.putx('other', st);
  insert into public.user_store_assignments (user_id, store_id) select pg_temp.fx(y.k), st from unnest(array['manager', 'staff']) y(k);
  -- The Adelphi centre and the Van & RoadShow, by their codes as production has them (482 refuses without the
  -- first); a copy without production's stores gets made-up ones for this run.
  insert into public.stores (name, code, country_code) values ('T482 Adelphi centre', 'RETAIL-ADELPHI', 'SG'),
                                                              ('T482 Van and RoadShow', 'ADELPHI-VAN', 'SG')
    on conflict (code) do nothing;
  perform pg_temp.putx('adelphi', (select s.id from public.stores s where s.code = 'RETAIL-ADELPHI'));
  perform pg_temp.putx('van', (select s.id from public.stores s where s.code = 'ADELPHI-VAN'));
  -- 480's migration row, as production has it (482 refuses without it); a copy built with psql holds none past 478.
  if not exists (select 1 from supabase_migrations.schema_migrations m where m.version = '20261030052953') then
    insert into supabase_migrations.schema_migrations (version, name) values ('20261030052953', '480_downline_and_network_show_calcom_booking');
    perform pg_temp.put('mig480_added', 'yes');
  end if;

  -- The referrer (an affiliate with a portal login) and their network.
  insert into public.customers (full_name, phone, email) values ('T482 Referrer Rae', pg_temp.ph(0), pg_temp.mail('rae')) returning id into r;
  perform pg_temp.putx('rae', r);
  insert into public.customer_affiliates (customer_id, status, store_id, activated_at) values (r, 'active', st, now()) returning id into aff;
  insert into public.affiliate_accounts (auth_user_id, customer_id, affiliate_id, status) values (pg_temp.fx('aff'), r, aff, 'claimed');
  -- Tier 1 (Rae's), then Tier 2 (under vis), then records outside the network (merged later).
  for x in select y.key, y.parent from (values
      ('vis', 'rae'), ('vtd', 'rae'), ('vfut', 'rae'),
      ('a_paid', 'rae'), ('a_partially_paid', 'rae'), ('a_completed_foc', 'rae'), ('a_refund_requested', 'rae'), ('a_refunded', 'rae'),
      ('adel', 'rae'), ('avan', 'rae'), ('aoth', 'rae'), ('aweb', 'rae'), ('avip', 'rae'), ('agst', 'rae'),
      ('bd_today', 'rae'), ('bd_null_today', 'rae'), ('bd_null_next', 'rae'), ('bd_past_later', 'rae'), ('bd_future', 'rae'),
      ('nothing', 'rae'), ('bup', 'rae'), ('bcame', 'rae'), ('bmiss', 'rae'), ('bcxl', 'rae'), ('bcxl0', 'rae'),
      ('mkeep', 'rae'), ('mkeep2', 'rae'), ('mkeep3', 'rae'),
      ('t2vis', 'vis'), ('t2adel', 'vis'), ('t2van', 'vis'), ('t2none', 'vis'), ('t2up', 'vis'),
      ('mdup', null), ('mdup2', null), ('mdup3', null)) y(key, parent) loop
    n := n + 1;
    insert into public.customers (full_name, phone, referred_by) values ('T482 ' || x.key, pg_temp.ph(n), pg_temp.fx(x.parent))
    returning id into v;
    perform pg_temp.putx(x.key, v);
  end loop;
  -- One customer for each invoice status that does not count (every label of invoice_status but the five counted,
  -- read from the catalogue: draft, unpaid, cancellation_requested and cancelled today).
  for x in select e.enumlabel::text as lbl from pg_enum e where e.enumtypid = 'public.invoice_status'::regtype
            and e.enumlabel not in ('paid', 'partially_paid', 'completed_foc', 'refund_requested', 'refunded') order by e.enumsortorder loop
    n := n + 1;
    insert into public.customers (full_name, phone, referred_by) values ('T482 x_' || x.lbl, pg_temp.ph(n), pg_temp.fx('rae'))
    returning id into v;
    perform pg_temp.putx('x_' || x.lbl, v);
    perform pg_temp.put('excluded', concat_ws(',', pg_temp.tx('excluded'), 'x_' || x.lbl));
  end loop;
  perform pg_temp.put('n_customers', n::text);

  -- Visits (the visit rule): an older one, one today, one dated two days ahead; the booked ones' and Tier 2's.
  perform pg_temp.visit('vis', pg_temp.sg(pg_temp.today() - 10, '11:00'));
  perform pg_temp.visit('vtd', now());
  perform pg_temp.visit('vfut', pg_temp.sg(pg_temp.today() + 2, '11:00'));
  perform pg_temp.visit('bup', pg_temp.sg(pg_temp.today() - 4, '11:00'));
  perform pg_temp.visit('bcame', pg_temp.sg(pg_temp.today() - 2, '15:00'));
  -- (A customer holds one survey: uq_health_survey_customer. bmiss came in before its booking by a visit, after it
  -- by a purchase.)
  perform pg_temp.visit('bmiss', pg_temp.sg(pg_temp.today() - 6, '11:00'));
  perform pg_temp.visit('bcxl', pg_temp.sg(pg_temp.today() - 3, '11:00'));
  perform pg_temp.visit('t2vis', pg_temp.sg(pg_temp.today() - 5, '11:00'));
  perform pg_temp.visit('mdup', pg_temp.sg(pg_temp.today() - 7, '11:00'));
  perform pg_temp.visit('mdup2', pg_temp.sg(pg_temp.today() - 7, '11:00'));

  -- Invoices, five days ago unless the case is about the day.
  perform pg_temp.putx('inv_' || y.k, pg_temp.inv(y.k, y.store, y.st, pg_temp.today() - 5, pg_temp.sg(pg_temp.today() - 5, '12:00'), y.del))
    from (values ('a_paid', 'adelphi', 'paid', false), ('a_partially_paid', 'adelphi', 'partially_paid', false),
                 ('a_completed_foc', 'adelphi', 'completed_foc', false), ('a_refund_requested', 'adelphi', 'refund_requested', false),
                 ('a_refunded', 'adelphi', 'refunded', false),
                 ('adel', 'adelphi', 'paid', true), ('avan', 'van', 'paid', false), ('aoth', 'other', 'paid', false),
                 ('aweb', 'adelphi', 'paid', false), ('avip', 'adelphi', 'paid', false), ('agst', 'adelphi', 'paid', false),
                 ('t2adel', 'adelphi', 'paid', false), ('t2van', 'van', 'paid', false), ('mdup3', 'adelphi', 'paid', false)) y(k, store, st, del);
  perform pg_temp.inv(u.xk, 'adelphi', substr(u.xk, 3), pg_temp.today() - 5, pg_temp.sg(pg_temp.today() - 5, '12:00'))
    from unnest(string_to_array(pg_temp.tx('excluded'), ',')) u(xk);
  perform pg_temp.inv('bd_today', 'adelphi', 'paid', pg_temp.today(), pg_temp.sg(pg_temp.today(), '09:00'));
  perform pg_temp.inv('bd_null_today', 'adelphi', 'paid', null, pg_temp.sg(pg_temp.today(), '00:30'));
  perform pg_temp.inv('bd_null_next', 'adelphi', 'paid', null, pg_temp.sg(pg_temp.today() + 1, '00:30'));
  perform pg_temp.inv('bd_past_later', 'adelphi', 'paid', pg_temp.today() - 1, pg_temp.sg(pg_temp.today() + 1, '12:00'));
  perform pg_temp.inv('bd_future', 'adelphi', 'paid', pg_temp.today() + 1, pg_temp.sg(pg_temp.today() - 3, '12:00'));
  -- The booked ones' purchases on other days than their bookings.
  perform pg_temp.inv('bup', 'adelphi', 'paid', pg_temp.today() - 4, pg_temp.sg(pg_temp.today() - 4, '12:00'));
  perform pg_temp.inv('bmiss', 'adelphi', 'paid', pg_temp.today() - 1, pg_temp.sg(pg_temp.today() - 1, '12:00'));
end $$;
-- The order rows only need to name the invoice: written as the server would, without their other records.
set local session_replication_role = replica;
insert into public.web_orders (channel, stripe_session_id, livemode, status, ticket, quantity, unit_amount_cents, amount_total_cents,
                               early_bird, buyer_name, checkout_opened_at, paid_at, invoice_id)
values ('t482', 'cs_t482_' || pg_temp.tx('sfx'), false, 'invoiced', 'fixture', 1, 0, 0, false, 'T482 Web Buyer', now(), now(), pg_temp.fx('inv_aweb'));
insert into public.event_vip_order_people (order_ref, person_id, position, invoice_id) values (gen_random_uuid(), gen_random_uuid(), 1, pg_temp.fx('inv_avip'));
insert into public.event_guests (event_id, name, source, invoice_id, invoice_item_id)
values (gen_random_uuid(), 'T482 guest', 'ticket', pg_temp.fx('inv_agst'), gen_random_uuid());
set local session_replication_role = origin;
-- Bookings (cal.com's webhook), each made with its customer's phone: upcoming, two days ago (came; missed), cancelled
-- only (two), and the record merged later's.
create temp table bk(k text primary key, at timestamptz, cancelled boolean);
insert into bk values ('bup', pg_temp.sg(pg_temp.today() + 5, '14:00'), false), ('bcame', pg_temp.sg(pg_temp.today() - 2, '11:00'), false),
                      ('bmiss', pg_temp.sg(pg_temp.today() - 2, '11:00'), false), ('bcxl', pg_temp.sg(pg_temp.today() + 1, '10:00'), true),
                      ('bcxl0', pg_temp.sg(pg_temp.today() - 1, '10:00'), true), ('t2up', pg_temp.sg(pg_temp.today() + 3, '16:00'), false),
                      ('mdup2', pg_temp.sg(pg_temp.today() + 4, '09:30'), false);
select pg_temp.put('b_' || bk.k, pg_temp.book(bk.k, bk.at, (select c.phone from public.customers c where c.id = pg_temp.fx(bk.k)))) from bk;
select pg_temp.put('x_' || bk.k, pg_temp.book(bk.k, bk.at, null, 'BOOKING_CANCELLED', now() - interval '10 days')) from bk where bk.cancelled;
set local client_min_messages = notice;
select pg_temp.check((select string_agg(bk.k || '=' || pg_temp.tx('b_' || bk.k) || coalesce('/' || pg_temp.tx('x_' || bk.k), ''), ' ' order by bk.k) from bk)
                     = 'bcame=created bcxl=created/updated bcxl0=created/updated bmiss=created bup=created mdup2=created t2up=created'
    and (select count(*) from public.calcom_bookings b join bk on b.uid = pg_temp.uid(bk.k)
          where b.status = case when bk.cancelled then 'cancelled' else 'active' end and b.start_at = bk.at
            and (bk.cancelled or b.phone_key = (select public.normalize_customer_phone(c.phone) from public.customers c where c.id = pg_temp.fx(bk.k)))) = 7,
  'F0 the fixture: each booking stored with its customer''s phone, two of them then cancelled');

-- What the two screens answered before 482 (only when this file installs it), as the Manager and as the affiliate.
\if :{?skip_install}
\else
select pg_temp.put('pre_dl', pg_temp.try_as('manager', format('select public.customer_downline_visits(%L::uuid)::text', pg_temp.fx('rae'))));
select pg_temp.put('pre_net', pg_temp.try_as('aff', 'select public.affiliate_portal_network()::text'));
create temp table pre_states as
select k.k, b.booking_state, b.booking_at from fx k cross join lateral public.calcom_customer_bookings(array[k.v]) b;
create temp table b482 as select * from pg_temp.fn_md5s();
create temp table r482 as select pg_temp.row_counts() as before, pg_temp.seqs() as seq_before;
\ir ../../../supabase/482_downline_and_network_show_visited_without_booking.sql
create temp table m482 as select * from pg_temp.fn_md5s();
alter table r482 add column after1 jsonb, add column seq_after1 jsonb;
update r482 set after1 = pg_temp.row_counts(), seq_after1 = pg_temp.seqs();
\ir ../../../supabase/482_downline_and_network_show_visited_without_booking.sql
create temp table m482b as select * from pg_temp.fn_md5s();
\endif

-- ═════ V 'visited' (Came in) or 'none': no booking ═════
select pg_temp.check(pg_temp.states(array['vis', 'vtd', 'vfut']) = 'vis=visited vtd=visited vfut=none'
    and pg_temp.st('vis') = 'visited' and pg_temp.st('vtd') = 'visited' and pg_temp.st('vfut') = 'none'
    and pg_temp.st0('vfut', pg_temp.today() + 1) = 'none' and pg_temp.st0('vfut', pg_temp.today() + 2) = 'visited'
    and pg_temp.st0('vis', pg_temp.today() - 11) = 'none' and pg_temp.st0('vis', pg_temp.today() - 10) = 'visited',
  'V1 a visit by the visit rule (ten days ago, or today) makes it visited, with no date; a visit dated after today counts only from its day: '
  || pg_temp.states(array['vis', 'vtd', 'vfut']));
select pg_temp.check(pg_temp.states(array['a_paid', 'a_partially_paid', 'a_completed_foc', 'a_refund_requested', 'a_refunded'])
                     = 'a_paid=visited a_partially_paid=visited a_completed_foc=visited a_refund_requested=visited a_refunded=visited',
  'V2 an invoice at the Adelphi centre, its money or FOC settled, makes it visited: paid, partially paid, FOC, refund requested, refunded: '
  || pg_temp.states(array['a_paid', 'a_partially_paid', 'a_completed_foc', 'a_refund_requested', 'a_refunded']));
select pg_temp.check((select bool_and(pg_temp.st0(k) = 'none') from unnest(string_to_array(pg_temp.tx('excluded'), ',')) k)
    and string_to_array(pg_temp.tx('excluded'), ',') @> array['x_draft', 'x_unpaid', 'x_cancellation_requested', 'x_cancelled']
    and (select count(*) from public.invoices i where i.customer_id = any (select pg_temp.fx(k) from unnest(string_to_array(pg_temp.tx('excluded'), ',')) k)
                                                  and i.store_id = pg_temp.fx('adelphi') and i.deleted_at is null)
        = cardinality(string_to_array(pg_temp.tx('excluded'), ',')),
  'V3 an Adelphi invoice of every other status (each label of invoice_status not counted) does not: '
  || pg_temp.states(string_to_array(pg_temp.tx('excluded'), ',')));
select pg_temp.check(pg_temp.states(array['adel', 'avan', 'aoth', 'aweb', 'avip', 'agst']) = 'adel=none avan=none aoth=none aweb=none avip=none agst=none',
  'V4 a deleted invoice, the Van & RoadShow, another store, and an Adelphi invoice that is an online (web) order, a VIP order or an event guest''s do not: '
  || pg_temp.states(array['adel', 'avan', 'aoth', 'aweb', 'avip', 'agst']));
-- The Adelphi centre is the store IN USE coded RETAIL-ADELPHI: with it deleted, or its code changed, its purchases
-- stop counting (a visit still does). Read in a savepoint into psql variables (a check's row would be undone too).
savepoint v4b;
update public.stores set deleted_at = now() where code = 'RETAIL-ADELPHI';
select pg_temp.states(array['a_paid', 'bd_today', 'vis']) as v4b_deleted \gset
rollback to savepoint v4b;
update public.stores set code = code || '-T482' where code = 'RETAIL-ADELPHI';
select pg_temp.states(array['a_paid', 'bd_today', 'vis']) as v4b_renamed \gset
rollback to savepoint v4b;
release savepoint v4b;
select pg_temp.check(:'v4b_deleted' = 'a_paid=none bd_today=none vis=visited' and :'v4b_renamed' = 'a_paid=none bd_today=none vis=visited'
    and pg_temp.states(array['a_paid', 'bd_today', 'vis']) = 'a_paid=visited bd_today=visited vis=visited',
  'V4b the Adelphi centre is the store in use coded RETAIL-ADELPHI: deleted, or its code changed, its purchases stop counting; a visit still counts: '
  || :'v4b_deleted' || ' / ' || :'v4b_renamed');
select pg_temp.check(pg_temp.states(array['bd_today', 'bd_null_today', 'bd_null_next', 'bd_past_later', 'bd_future'])
                     = 'bd_today=visited bd_null_today=visited bd_null_next=none bd_past_later=visited bd_future=none'
    and pg_temp.st0('bd_future', pg_temp.today() + 1) = 'visited' and pg_temp.st0('bd_null_next', pg_temp.today() + 1) = 'visited'
    and pg_temp.st0('bd_past_later', pg_temp.today() - 2) = 'none',
  'V5 the day is the business date, else the Singapore date it was made: dated today, or made today with no date, counts; made 12.30 am tomorrow (today in UTC) does not; dated yesterday though made later counts; dated tomorrow does not until that day: '
  || pg_temp.states(array['bd_today', 'bd_null_today', 'bd_null_next', 'bd_past_later', 'bd_future']));
select pg_temp.check(pg_temp.st('nothing') = 'none' and pg_temp.st('t2none') = 'none',
  'V6 nothing at all: none (the red No booking)');
select pg_temp.check((select count(*) from public.calcom_customer_bookings(array[pg_temp.fx('vis'), pg_temp.fx('nothing'), gen_random_uuid(), null])) = 2
    and (select count(*) from public.calcom_customer_bookings(null)) = 0
    and (select count(*) from public.calcom_customer_bookings('{}')) = 0
    and (select string_agg(b.booking_state || ':' || coalesce(b.booking_at::text, '-'), ' ' order by b.booking_state)
           from public.calcom_customer_bookings(array[pg_temp.fx('vis'), pg_temp.fx('nothing')]) b) = 'none:- visited:-',
  'V7 one row per customer in use asked about (an unknown id and a null give none); visited and none carry no booking time');

-- ═════ K A booking keeps its state ═════
select pg_temp.check(pg_temp.st('bup') = 'upcoming ' || pg_temp.iso(pg_temp.sg(pg_temp.today() + 5, '14:00'))
    and pg_temp.st('bcame') = 'came ' || pg_temp.iso(pg_temp.sg(pg_temp.today() - 2, '11:00'))
    and pg_temp.st('bmiss') = 'miss ' || pg_temp.iso(pg_temp.sg(pg_temp.today() - 2, '11:00'))
    and pg_temp.st('t2up') = 'upcoming ' || pg_temp.iso(pg_temp.sg(pg_temp.today() + 3, '16:00')),
  'K1 a customer with a booking keeps its state: upcoming (with a visit and a purchase before it), came (a visit that day), miss (a visit and a purchase on other days, before and after it)');
select pg_temp.check(pg_temp.st('bcxl') = 'visited' and pg_temp.st('bcxl0') = 'none',
  'K2 only cancelled bookings are no booking: visited when they came in (a visit), else none');
select pg_temp.check(pg_temp.st0('bmiss', pg_temp.today() + 30) = 'miss' and pg_temp.st0('bcame', pg_temp.today() + 30) = 'came'
    and pg_temp.st0('bup', pg_temp.today() + 6) = 'miss',
  'K3 later days change nothing: a Miss stays a Miss, a came stays came; an upcoming booking with no visit that day becomes a Miss (never visited)');

-- ═════ R The two screens' rows ═════
select pg_temp.put('dl', pg_temp.try_as('manager', format('select public.customer_downline_visits(%L::uuid)::text', pg_temp.fx('rae'))));
select pg_temp.put('net', pg_temp.try_as('aff', 'select public.affiliate_portal_network()::text'));
create temp table want(name text primary key, tier text, state text, at timestamptz);
insert into want
select 'T482 ' || y.k, y.tier, y.state, y.at from (values
    ('vis', 'tier1', 'visited', null::timestamptz), ('vtd', 'tier1', 'visited', null), ('vfut', 'tier1', 'none', null),
    ('a_paid', 'tier1', 'visited', null), ('a_partially_paid', 'tier1', 'visited', null), ('a_completed_foc', 'tier1', 'visited', null),
    ('a_refund_requested', 'tier1', 'visited', null), ('a_refunded', 'tier1', 'visited', null),
    ('adel', 'tier1', 'none', null), ('avan', 'tier1', 'none', null), ('aoth', 'tier1', 'none', null), ('aweb', 'tier1', 'none', null),
    ('avip', 'tier1', 'none', null), ('agst', 'tier1', 'none', null),
    ('bd_today', 'tier1', 'visited', null), ('bd_null_today', 'tier1', 'visited', null), ('bd_null_next', 'tier1', 'none', null),
    ('bd_past_later', 'tier1', 'visited', null), ('bd_future', 'tier1', 'none', null), ('nothing', 'tier1', 'none', null),
    ('bup', 'tier1', 'upcoming', pg_temp.sg(pg_temp.today() + 5, '14:00')), ('bcame', 'tier1', 'came', pg_temp.sg(pg_temp.today() - 2, '11:00')),
    ('bmiss', 'tier1', 'miss', pg_temp.sg(pg_temp.today() - 2, '11:00')), ('bcxl', 'tier1', 'visited', null), ('bcxl0', 'tier1', 'none', null),
    ('mkeep', 'tier1', 'none', null), ('mkeep2', 'tier1', 'none', null), ('mkeep3', 'tier1', 'none', null),
    ('t2vis', 'tier2', 'visited', null), ('t2adel', 'tier2', 'visited', null), ('t2van', 'tier2', 'none', null),
    ('t2none', 'tier2', 'none', null), ('t2up', 'tier2', 'upcoming', pg_temp.sg(pg_temp.today() + 3, '16:00'))) y(k, tier, state, at)
union all
select 'T482 ' || k, 'tier1', 'none', null from unnest(string_to_array(pg_temp.tx('excluded'), ',')) k;
create function pg_temp.want_rows(tier text) returns jsonb language sql as
$$ select coalesce(jsonb_object_agg(w.name, jsonb_build_array(w.state, to_jsonb(w.at))), '{}'::jsonb) from want w where w.tier = $1 $$;
select pg_temp.check(pg_temp.state(pg_temp.tx('dl')) = 'ok'
    and pg_temp.rows_by(pg_temp.body(pg_temp.tx('dl'))::jsonb, 'tier1', 'name') = pg_temp.want_rows('tier1')
    and pg_temp.rows_by(pg_temp.body(pg_temp.tx('dl'))::jsonb, 'tier2', 'name') = pg_temp.want_rows('tier2'),
  'R1 the Downline (a Manager): every Tier 1 and Tier 2 row''s booking_state and booking_at as the rule says: visited (no time) for those who came in without a booking, none for the others, bookings as before');
select pg_temp.check(pg_temp.state(pg_temp.tx('net')) = 'ok'
    and pg_temp.rows_by(pg_temp.body(pg_temp.tx('net'))::jsonb, 'tier1', 'customer_name') = pg_temp.want_rows('tier1')
    and pg_temp.rows_by(pg_temp.body(pg_temp.tx('net'))::jsonb, 'tier2', 'customer_name') = pg_temp.want_rows('tier2'),
  'R2 My Network (the affiliate''s own): the same booking state and time on every Tier 1 and Tier 2 row');
select pg_temp.check((select bool_and(r ->> 'booking_state' = pg_temp.st0(substr(r ->> 'name', 6)))
                        from (select jsonb_array_elements(d -> 'tier1') r from (select pg_temp.body(pg_temp.tx('dl'))::jsonb d) z
                              union all select jsonb_array_elements(d -> 'tier2') from (select pg_temp.body(pg_temp.tx('dl'))::jsonb d) z) x)
    and (select count(*) from jsonb_array_elements(pg_temp.body(pg_temp.tx('dl'))::jsonb -> 'tier1')) = (select count(*) from want where tier = 'tier1')
    and (select count(*) from jsonb_array_elements(pg_temp.body(pg_temp.tx('dl'))::jsonb -> 'tier2')) = (select count(*) from want where tier = 'tier2'),
  'R3 the screens pass the state rule''s answer through, row for row');
select pg_temp.check((select bool_and((select array_agg(k order by k) from jsonb_object_keys(r) k)
                        = array['booking_at', 'booking_state', 'customer_id', 'first_visit_on', 'joined_from_created', 'joined_on', 'name', 'phone', 'visited'])
                        from jsonb_array_elements(pg_temp.body(pg_temp.tx('dl'))::jsonb -> 'tier1') r)
    and (select bool_and((select array_agg(k order by k) from jsonb_object_keys(r) k)
                        = array['booking_at', 'booking_state', 'customer_id', 'first_visit_on', 'joined_from_created', 'joined_on', 'name', 'parent_id',
                                'parent_name', 'phone', 'visited'])
                        from jsonb_array_elements(pg_temp.body(pg_temp.tx('dl'))::jsonb -> 'tier2') r)
    and (select array_agg(k order by k) from jsonb_object_keys(pg_temp.body(pg_temp.tx('dl'))::jsonb) k) = array['customer_id', 'name', 'phone', 'tier1', 'tier2']
    and (select bool_and((select array_agg(k order by k) from jsonb_object_keys(r) k)
                        = array['booking_at', 'booking_state', 'customer_name', 'joined_at', 'purchases', 'referral_date', 'tier', 'total_spent', 'your_commission'])
                        from jsonb_array_elements(pg_temp.body(pg_temp.tx('net'))::jsonb -> 'tier1') r)
    and (select bool_and((select array_agg(k order by k) from jsonb_object_keys(r) k)
                        = array['booking_at', 'booking_state', 'customer_name', 'joined_at', 'parent_name', 'purchases', 'referral_date', 'tier', 'total_spent',
                                'your_commission'])
                        from jsonb_array_elements(pg_temp.body(pg_temp.tx('net'))::jsonb -> 'tier2') r)
    and (select array_agg(k order by k) from jsonb_object_keys(pg_temp.body(pg_temp.tx('net'))::jsonb) k) = array['tier1', 'tier2']
    and pg_temp.body(pg_temp.tx('net')) !~ '\+6125550' and pg_temp.body(pg_temp.tx('net')) !~* '@example',
  'R4 each row has the keys it had (480''s), nothing else; the answers'' top-level keys as before; the portal shows no phone or email');
select pg_temp.check((select jsonb_object_agg(r ->> 'name', jsonb_build_array(r -> 'visited', r -> 'first_visit_on'))
                        from jsonb_array_elements(pg_temp.body(pg_temp.tx('dl'))::jsonb -> 'tier1') r
                       where r ->> 'name' in ('T482 vis', 'T482 a_paid', 'T482 bd_today', 'T482 vfut', 'T482 nothing'))
                     = jsonb_build_object('T482 vis', jsonb_build_array(true, to_jsonb((pg_temp.today() - 10)::text)),
                                          'T482 a_paid', jsonb_build_array(false, null), 'T482 bd_today', jsonb_build_array(false, null),
                                          'T482 vfut', jsonb_build_array(true, to_jsonb((pg_temp.today() + 2)::text)),
                                          'T482 nothing', jsonb_build_array(false, null))
    and not exists (select 1 from public.customer_centre_visits() v where v.customer_id in (pg_temp.fx('a_paid'), pg_temp.fx('bd_today'), pg_temp.fx('t2adel'))),
  'R5 Visited and First visit are as they were: a purchase is not a visit (Visited No beside Booking ''visited'', which reads Came in), and a visit dated after today shows there with its date (Booking: none until that day)');
select pg_temp.check(pg_temp.try_as(w.k, format('select public.customer_downline_visits(%L::uuid)::text', pg_temp.fx('rae'))) = pg_temp.tx('dl'),
  format('R6 %s gets exactly the Manager''s Downline', w.label))
  from (values ('owner', 'the Owner'), ('staff', 'Staff'), ('service', 'the service role'), ('server', 'the server')) w(k, label);
\if :{?skip_install}
\else
select pg_temp.check(pg_temp.state(pg_temp.tx('pre_dl')) = 'ok' and pg_temp.state(pg_temp.tx('pre_net')) = 'ok'
    -- The Downline before 482, with each row that came in without a booking read as 482 reads it: word for word, in order.
    and (select jsonb_set(jsonb_set(d, '{tier1}', (select coalesce(jsonb_agg(case when w.state = 'visited' then jsonb_set(r, '{booking_state}', '"visited"') else r end order by n), '[]')
                                                   from jsonb_array_elements(d -> 'tier1') with ordinality t(r, n) left join want w on w.name = r ->> 'name')),
                          '{tier2}', (select coalesce(jsonb_agg(case when w.state = 'visited' then jsonb_set(r, '{booking_state}', '"visited"') else r end order by n), '[]')
                                      from jsonb_array_elements(d -> 'tier2') with ordinality t(r, n) left join want w on w.name = r ->> 'name'))
           from (select pg_temp.body(pg_temp.tx('pre_dl'))::jsonb as d) x)
        = pg_temp.body(pg_temp.tx('dl'))::jsonb
    and (select bool_and(r ->> 'booking_state' = 'none') from jsonb_array_elements(pg_temp.body(pg_temp.tx('pre_dl'))::jsonb -> 'tier1') r
          join want w on w.name = r ->> 'name' and w.state = 'visited')
    and (select bool_and(r ->> 'booking_state' = 'none') from jsonb_array_elements(pg_temp.body(pg_temp.tx('pre_dl'))::jsonb -> 'tier2') r
          join want w on w.name = r ->> 'name' and w.state = 'visited')
    -- My Network: the same set of rows (they tie on their order), the same change.
    and (select jsonb_build_object(
                  'tier1', (select coalesce(jsonb_agg(y.r order by y.r::text), '[]')
                              from (select case when w.state = 'visited' then jsonb_set(r, '{booking_state}', '"visited"') else r end as r
                                      from jsonb_array_elements(d -> 'tier1') r left join want w on w.name = r ->> 'customer_name') y),
                  'tier2', (select coalesce(jsonb_agg(y.r order by y.r::text), '[]')
                              from (select case when w.state = 'visited' then jsonb_set(r, '{booking_state}', '"visited"') else r end as r
                                      from jsonb_array_elements(d -> 'tier2') r left join want w on w.name = r ->> 'customer_name') y))
           from (select pg_temp.body(pg_temp.tx('pre_net'))::jsonb as d) x)
        = (select jsonb_build_object(
                  'tier1', (select coalesce(jsonb_agg(r order by r::text), '[]') from jsonb_array_elements(d -> 'tier1') r),
                  'tier2', (select coalesce(jsonb_agg(r order by r::text), '[]') from jsonb_array_elements(d -> 'tier2') r))
             from (select pg_temp.body(pg_temp.tx('net'))::jsonb as d) x),
  'R7 before 482 the same rows read none; after it, every row is word for word what it was but none -> visited for those who came in, the Downline''s rows in the same order');
select pg_temp.check((select string_agg(p.k || ':' || p.booking_state || '->' || b.booking_state, ' ' order by p.k)
                        from pre_states p cross join lateral public.calcom_customer_bookings(array[pg_temp.fx(p.k)]) b
                       where (p.booking_state, p.booking_at) is distinct from (b.booking_state, b.booking_at))
                     = (select string_agg(z.k || ':none->visited', ' ' order by z.k)
                          from (select substr(w.name, 6) as k from want w where w.state = 'visited' union all values ('mdup'), ('mdup3')) z)
    and (select count(*) from pre_states p join want w on substr(w.name, 6) = p.k) = (select count(*) from want),
  'R8 the state rule before and after 482, for every customer of the fixture (the network, and the records merged later): only none -> visited, for exactly those who came in');
\endif

-- ═════ M Merges ═════
-- As the Customers page does it (an Owner, merge_customer_records): mdup (a visit) into mkeep, mdup2 (a booking made
-- with its own phone, and a visit) into mkeep2, mdup3 (an Adelphi purchase) into mkeep3.
select pg_temp.put('m_before', pg_temp.states(array['mkeep', 'mkeep2', 'mkeep3', 'mdup', 'mdup2', 'mdup3']));
do $$ begin
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform public.merge_customer_records(pg_temp.fx('mkeep'), pg_temp.fx('mdup'), 'T482 fixture merge, a visit', gen_random_uuid());
  perform public.merge_customer_records(pg_temp.fx('mkeep2'), pg_temp.fx('mdup2'), 'T482 fixture merge, a booking', gen_random_uuid());
  perform public.merge_customer_records(pg_temp.fx('mkeep3'), pg_temp.fx('mdup3'), 'T482 fixture merge, a purchase', gen_random_uuid());
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
end $$;
select pg_temp.check(pg_temp.tx('m_before') = 'mkeep=none mkeep2=none mkeep3=none mdup=visited mdup2=upcoming mdup3=visited'
    and (select count(*) from public.customers where id in (pg_temp.fx('mdup'), pg_temp.fx('mdup2'), pg_temp.fx('mdup3')) and deleted_at is not null) = 3
    and pg_temp.st('mkeep2') = 'upcoming ' || pg_temp.iso(pg_temp.sg(pg_temp.today() + 4, '09:30'))
    and public.calcom_booking_owner((select public.normalize_customer_phone(c.phone) from public.customers c where c.id = pg_temp.fx('mdup2')), null)
        = pg_temp.fx('mkeep2'),
  'M1 a merged record''s booking still follows the merge: the kept record shows it (upcoming), not visited: ' || pg_temp.tx('m_before'));
select pg_temp.check(pg_temp.st('mkeep') = 'visited' and pg_temp.st('mkeep3') = 'visited'
    and pg_temp.st0('mdup') is null and pg_temp.st0('mdup3') is null,
  'M2 the merge moves the merged record''s visit and Adelphi invoice to the kept record, which reads visited (the merged record has no row)');
select pg_temp.put('m_dl', pg_temp.try_as('manager', format('select public.customer_downline_visits(%L::uuid)::text', pg_temp.fx('rae'))));
select pg_temp.put('m_net', pg_temp.try_as('aff', 'select public.affiliate_portal_network()::text'));
select pg_temp.check(pg_temp.rows_by(pg_temp.body(pg_temp.tx('m_dl'))::jsonb, 'tier1', 'name') @> jsonb_build_object(
          'T482 mkeep', jsonb_build_array('visited', null), 'T482 mkeep3', jsonb_build_array('visited', null),
          'T482 mkeep2', jsonb_build_array('upcoming', to_jsonb(pg_temp.sg(pg_temp.today() + 4, '09:30'))))
    and pg_temp.rows_by(pg_temp.body(pg_temp.tx('m_net'))::jsonb, 'tier1', 'customer_name')
        = pg_temp.rows_by(pg_temp.body(pg_temp.tx('m_dl'))::jsonb, 'tier1', 'name'),
  'M3 both screens show the kept records so: visited (Came in) for the moved visit and purchase, the followed booking for the other');

-- ═════ P Who may ═════
select pg_temp.check(pg_temp.state(pg_temp.try_as('service', format('select count(*)::text from public.calcom_customer_bookings(array[%L::uuid])', pg_temp.fx('vis')))) = 'ok'
    and pg_temp.state(pg_temp.try_as('owner', format('select count(*)::text from public.calcom_customer_bookings(array[%L::uuid])', pg_temp.fx('vis')))) = '42501'
    and pg_temp.state(pg_temp.try_as('staff', format('select count(*)::text from public.calcom_customer_bookings(array[%L::uuid])', pg_temp.fx('vis')))) = '42501'
    and pg_temp.state(pg_temp.try_as('aff', format('select count(*)::text from public.calcom_customer_bookings(array[%L::uuid])', pg_temp.fx('vis')))) = '42501'
    and pg_temp.state(pg_temp.try_as('anon', format('select count(*)::text from public.calcom_customer_bookings(array[%L::uuid])', pg_temp.fx('vis')))) = '42501'
    and pg_temp.state(pg_temp.try_as('anon', format('select public.customer_downline_visits(%L::uuid)::text', pg_temp.fx('rae')))) = '42501'
    and pg_temp.state(pg_temp.try_as('anon', 'select public.affiliate_portal_network()::text')) = '42501',
  'P1 the state rule: the service role may; an Owner, Staff, an affiliate and signed out may not (42501); signed out cannot reach either screen');

-- ═════ G md5s and grants ═════
select pg_temp.check((select array_agg(f.fn || ' ' || f.md5 order by f.fn) from pg_temp.fn_md5s() f
                       where f.fn like 'calcom%' or f.fn in ('customer_downline_visits(uuid)', 'affiliate_portal_network()'))
    = array['affiliate_portal_network() d1c387fb852392da041b5d8207655879',
            'calcom_booking_apply(text,text,timestamp with time zone,timestamp with time zone,bigint,text,text,text,timestamp with time zone,text,text) 844d56ae966ca4e1e633e070e0195256',
            'calcom_booking_backfill(jsonb,timestamp with time zone,timestamp with time zone,timestamp with time zone,boolean,text[],boolean) b68af462ad32de7af3f8b98a8491a7e1',
            'calcom_booking_ingest(jsonb) 55d6b6b8b7509911a225f494313212d9',
            'calcom_booking_owner(text,text) 959a5a8280ac20155068b3fa9aae73f3',
            'calcom_customer_bookings(uuid[],date) 14987e9e9f033290010042a5632bc81c',
            'calcom_parse_time(text) 773399bc477ceb3476dd84a6a9251f2d',
            'customer_downline_visits(uuid) ea3f28ea932506eda6937fa687298d6d'],
  'G1 the state rule is at 482''s AFTER md5; the two screens'' functions and the other cal.com functions are still 480''s');
select pg_temp.check((select array_agg(p.proname || ' ' || (select array_agg(x::text order by x::text) from unnest(p.proacl) x)::text order by p.proname)
                        from pg_proc p where p.pronamespace = 'public'::regnamespace
                         and p.proname in ('calcom_customer_bookings', 'customer_downline_visits', 'affiliate_portal_network'))
    = array['affiliate_portal_network {authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres}',
            'calcom_customer_bookings {postgres=X/postgres,service_role=X/postgres}',
            'customer_downline_visits {authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres}']
    and (select p.prosecdef and p.provolatile = 's' and p.proconfig = array['search_path=public'] and l.lanname = 'sql'
           from pg_proc p join pg_language l on l.oid = p.prolang where p.oid = 'public.calcom_customer_bookings(uuid[],date)'::regprocedure),
  'G2 grants (as sets): the state rule the owner''s and the service role''s; the two screens as before; the state rule still LANGUAGE sql STABLE SECURITY DEFINER with search_path public');
select pg_temp.check((select array_agg(f.fn || ' ' || f.md5 order by f.fn) from pg_temp.fn_md5s() f
                       where f.fn in ('customer_centre_visit_days()', 'customer_centre_visits()', 'normalize_customer_phone(text)',
                                      'customer_email_match_key(text)', 'sg_today()', 'merge_customer_records(uuid,uuid,text,uuid)'))
    = array['customer_centre_visit_days() 2129857d6ff9f29dcf2cbccc9f13e5bc', 'customer_centre_visits() c07a5a0cbbf52ba45e5dc911b20002da',
            'customer_email_match_key(text) be468815c9626fff1728e2cfcd484b66',
            'merge_customer_records(uuid,uuid,text,uuid) ba05c2b1fb4c0e14d369c01d06a635b0',
            'normalize_customer_phone(text) b2bfac910e0c9eff402ba44e19750bee', 'sg_today() 1c1289f18e24d8370e9a6364c9c06fca'],
  'G3 what it relies on is unchanged (the visit rule and Visited/First visit, the phone and email readers, sg_today, the merge)');

-- ═════ N 482 twice; refusals ═════
\if :{?skip_install}
\else
select pg_temp.check(not exists (select 1 from m482 m full join m482b b on b.fn = m.fn where m.fn is null or b.fn is null or b.md5 <> m.md5),
  'N1 running 482 a second time changed no function');
select pg_temp.check((select coalesce(array_agg(m.fn || ' ' || b.md5 || ' -> ' || m.md5 order by m.fn), '{}') from m482 m left join b482 b on b.fn = m.fn
                       where b.fn is null or b.md5 <> m.md5)
                     = array['calcom_customer_bookings(uuid[],date) 2e651a5d2367ba26bfd9e8e00d95823e -> 14987e9e9f033290010042a5632bc81c']
    and (select count(*) from m482) = (select count(*) from b482),
  'N2 its first run changed the state rule from 480''s to 482''s and nothing else (no function added, dropped or changed)');
select pg_temp.check((select after1 = before from r482),
  'N3 482''s self-test left no row (every table of public and auth counts the same before and after it)');
select pg_temp.check((select seq_after1 = seq_before from r482),
  'N4 and moved no sequence: ' || (select coalesce(string_agg(k, ', '), 'none') from r482, jsonb_each(seq_after1) e(k, v) where seq_before -> k is distinct from v));
\endif
-- Run where 482 is in: "already this version; left alone", nothing changed.
create temp table m482c as select * from pg_temp.fn_md5s();
savepoint n4b;
\ir ../../../supabase/482_downline_and_network_show_visited_without_booking.sql
select pg_temp.check(not exists (select 1 from m482c m full join pg_temp.fn_md5s() b on b.fn = m.fn where m.fn is null or b.fn is null or b.md5 <> m.md5),
  'N4b 482 run again where it is in changes nothing (already this version; left alone)');
rollback to savepoint n4b;
-- A state rule changed since (a comment added): refused, nothing changed.
savepoint n5;
do $$ begin
  perform set_config('search_path', 'public', true);
  execute regexp_replace(pg_get_functiondef('public.calcom_customer_bookings(uuid[],date)'::regprocedure),
                         'AS \$function\$', 'AS $function$ -- changed by the 482 suite');
end $$;
reset search_path;
\echo 'N5: 482 is expected to refuse here (an ERROR is printed):'
\set ON_ERROR_STOP off
\ir ../../../supabase/482_downline_and_network_show_visited_without_booking.sql
\set ON_ERROR_STOP on
\set n5_msg :LAST_ERROR_MESSAGE
rollback to savepoint n5;
select pg_temp.check(:'n5_msg' like '482: public.calcom_customer_bookings(uuid[],date) is neither 480''s version (production, 30 Oct 2026) nor this file''s%Re-read it and re-test before applying.',
  'N5 a state rule changed since is refused (all undone): ' || :'n5_msg');
-- Without 480's migration row: refused.
savepoint n6;
delete from supabase_migrations.schema_migrations where version = '20261030052953';
\echo 'N6: 482 is expected to refuse here (an ERROR is printed):'
\set ON_ERROR_STOP off
\ir ../../../supabase/482_downline_and_network_show_visited_without_booking.sql
\set ON_ERROR_STOP on
\set n6_msg :LAST_ERROR_MESSAGE
rollback to savepoint n6;
select pg_temp.check(:'n6_msg' like '482: 480 (20261030052953) is not recorded in supabase_migrations.schema_migrations.%',
  'N6 a database without 480''s migration row is refused: ' || :'n6_msg');
-- The Adelphi centre is found by its code: refused unless exactly one store in use has it (renamed, or deleted).
savepoint n7;
update public.stores set code = code || '-T482' where code = 'RETAIL-ADELPHI';
\echo 'N7: 482 is expected to refuse here (an ERROR is printed):'
\set ON_ERROR_STOP off
\ir ../../../supabase/482_downline_and_network_show_visited_without_booking.sql
\set ON_ERROR_STOP on
\set n7_msg :LAST_ERROR_MESSAGE
rollback to savepoint n7;
savepoint n7b;
update public.stores set deleted_at = now() where code = 'RETAIL-ADELPHI';
\echo 'N7: 482 is expected to refuse here too (an ERROR is printed):'
\set ON_ERROR_STOP off
\ir ../../../supabase/482_downline_and_network_show_visited_without_booking.sql
\set ON_ERROR_STOP on
\set n7b_msg :LAST_ERROR_MESSAGE
rollback to savepoint n7b;
select pg_temp.check(:'n7_msg' = '482: exactly one store in use must be coded RETAIL-ADELPHI (the Adelphi centre); found 0'
    and :'n7b_msg' = '482: exactly one store in use must be coded RETAIL-ADELPHI (the Adelphi centre); found 0',
  'N7 with the Adelphi store renamed, or deleted, 482 is refused: ' || :'n7_msg');
-- The visit rule, or the Downline's function, changed since: refused.
savepoint n8;
do $$ begin
  perform set_config('search_path', 'public', true);
  execute regexp_replace(pg_get_functiondef('public.customer_centre_visit_days()'::regprocedure), 'AS \$function\$', 'AS $function$ -- changed by the 482 suite');
end $$;
reset search_path;
\echo 'N8: 482 is expected to refuse here (an ERROR is printed):'
\set ON_ERROR_STOP off
\ir ../../../supabase/482_downline_and_network_show_visited_without_booking.sql
\set ON_ERROR_STOP on
\set n8_msg :LAST_ERROR_MESSAGE
rollback to savepoint n8;
savepoint n8b;
do $$ begin
  perform set_config('search_path', 'public', true);
  execute regexp_replace(pg_get_functiondef('public.customer_downline_visits(uuid)'::regprocedure), 'AS \$function\$', 'AS $function$ -- changed by the 482 suite');
end $$;
reset search_path;
\echo 'N8: 482 is expected to refuse here too (an ERROR is printed):'
\set ON_ERROR_STOP off
\ir ../../../supabase/482_downline_and_network_show_visited_without_booking.sql
\set ON_ERROR_STOP on
\set n8b_msg :LAST_ERROR_MESSAGE
rollback to savepoint n8b;
select pg_temp.check(:'n8_msg' = '482: public.customer_centre_visit_days() is missing or not the version this was tested against. Re-read it and re-test before applying.'
    and :'n8b_msg' = '482: public.customer_downline_visits(uuid) is missing or not the version this was tested against. Re-read it and re-test before applying.',
  'N8 a visit rule or a Downline function changed since is refused: ' || :'n8_msg');
-- A grant added to the state rule: refused.
savepoint n9;
grant execute on function public.calcom_customer_bookings(uuid[], date) to authenticated;
\echo 'N9: 482 is expected to refuse here (an ERROR is printed):'
\set ON_ERROR_STOP off
\ir ../../../supabase/482_downline_and_network_show_visited_without_booking.sql
\set ON_ERROR_STOP on
\set n9_msg :LAST_ERROR_MESSAGE
rollback to savepoint n9;
select pg_temp.check(:'n9_msg' = '482: the grants of public.calcom_customer_bookings(uuid[],date) are not as read on 30 Oct 2026 (the owner and the service role only)',
  'N9 a state rule granted to signed-in users is refused: ' || :'n9_msg');
-- 480's file cannot run over 482 (it refuses at the state rule, which is no longer its own).
savepoint n10;
\echo 'N10: 480 is expected to refuse here (an ERROR is printed):'
\set ON_ERROR_STOP off
\ir ../../../supabase/480_downline_and_network_show_calcom_booking.sql
\set ON_ERROR_STOP on
\set n10_msg :LAST_ERROR_MESSAGE
rollback to savepoint n10;
select pg_temp.check(:'n10_msg' like '480: public.calcom_customer_bookings(uuid[],date) exists and is not this migration''s (md5 14987e9e9f033290010042a5632bc81c)%',
  'N10 480''s file refuses to run over 482: ' || :'n10_msg');
select pg_temp.check(pg_temp.md5_of('calcom_customer_bookings(uuid[],date)') = '14987e9e9f033290010042a5632bc81c'
    and (select count(*) from public.stores where code = 'RETAIL-ADELPHI' and deleted_at is null) = 1
    and exists (select 1 from supabase_migrations.schema_migrations where version = '20261030052953')
    and pg_temp.md5_of('customer_centre_visit_days()') = '2129857d6ff9f29dcf2cbccc9f13e5bc'
    and pg_temp.md5_of('customer_downline_visits(uuid)') = 'ea3f28ea932506eda6937fa687298d6d'
    and (select array_agg(x::text order by x::text) from pg_proc p, unnest(p.proacl) x where p.oid = 'public.calcom_customer_bookings(uuid[],date)'::regprocedure)
        = array['postgres=X/postgres', 'service_role=X/postgres'],
  'N11 after the refusals everything is as it was (the state rule 482''s, the store, the migration row, the visit rule, the Downline, the grants)');

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All 482 checks passed.';
end $$;
rollback;
