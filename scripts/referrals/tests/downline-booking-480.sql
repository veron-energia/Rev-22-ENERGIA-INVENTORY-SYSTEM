-- cal.com bookings on the Downline and on the affiliate portal's My Network (480).
--
-- The Owner's request and answers, 29 Oct 2026: each Tier 1 and Tier 2 customer's cal.com booking, seen
-- by staff, Owners, Managers and the customer's affiliate. The next booking whose Singapore day is today
-- or later; else the most recent past one; cancelled and rescheduled-away ones ignored. "Miss" when the
-- day is over and that day the customer has no visit by the visit rule (customer_centre_visit_days) and no
-- settled purchase at the Adelphi centre; "No booking" when there is none. Bookings arrive by cal.com's
-- webhook (calcom_booking_ingest) and from Google Calendar (calcom_booking_backfill: the first fill and the
-- monthly catch-up, one call), and belong to a customer by phone, then email, then along a merge, worked
-- out whenever they are read.
--
--   I  Ingest: created; the same event again (nothing changes); an older event (stale); rescheduled to
--      a new uid (rescheduleUid and fromReschedule: the old one rescheduled away, also when never seen)
--      and to a new time under the same uid; cancelled (also a uid never seen, which a late CREATED
--      cannot bring back); a cancellation at the same moment as the creation; triggers that are not
--      read (ignored, nothing stored); the phone from the WhatsApp-Number answer, else the attendee's
--      phone, else the smsReminderNumber answer; the email from the answer, else the attendee's; what
--      is stored (no name, answers or title); malformed bodies refused with 22023 naming the field and
--      never quoting a value; a number the centre keeps as its own (ads_excluded_phones) is no one's,
--      as in the calendar fill (I13); an answer that is not text is not read (I14).
--   B  Calendar fill and monthly catch-up (ONE window, every event listed): a booking not seen before is
--      created (a "Cxl" title stays a booking; the uid from the LAST cal.com link, not one typed in a note
--      before it (B7); a time written without an offset read in its timeZone); a fill's or the webhook's
--      booking is moved by a newer Google event; an older one changes nothing: unchanged when it agrees
--      (cal.com writes its Google event a moment before its webhook, B17), else stale and listed
--      (kept_newer); an event listed cancelled cancels; a cancelled or rescheduled-away booking is never
--      brought back (terminal); skipped and counted, the call going on: all-day, no cal.com link (kept as
--      gcal:<id> when asked), no number in a new booking's title (a stored booking is still moved), shapes
--      that cannot be read, an 'updated' later than now (B15); a uid listed more than once (a staff
--      Duplicate copies cal.com's link): the copy at the stored start, else a stored booking's copy
--      updated last, a new booking's earliest, each other copy listed (B8, B8b); no 'updated': when the
--      listing began, counted (B16); missing_from_calendar reported in dry and real runs and listed first
--      (B11b), cancelled only on a real run naming its uid in p_cancel_uids, also when that run's listing
--      lost a page (B14), never for a booking outside the window or changed after the listing began; a dry
--      run writes nothing and counts what the real run does; the same listing again changes nothing; a
--      webhook after a fill is ordered by its time; refused: not an array, more than 5000 events, a
--      missing or too long window, a missing or future p_listed_at, p_cancel_uids with nothing listed, a
--      call in round 2's boolean form (B9b); the answer: counts, and uids and times only (at most 500
--      changes, then truncated).
--   M  Matching: by phone; a shared phone narrowed by the email (Gmail spellings one inbox); the email
--      alone; ambiguous (two by email, or a shared phone with no deciding email) = no one; a deleted
--      customer is not anyone (a live one on the same phone is); a merge of twins on one phone: the kept
--      record takes the booking; a merged record's booking follows the merge (the Owner, 29 Oct 2026):
--      the kept record with another phone and email (M3b), a chain A into B into C (M5), two duplicates on
--      one phone merged into two customers: no one (M6), a record deleted with Delete (M7) or restored
--      after its merge and deleted again (M8) is not followed, a customer in use holding the phone wins
--      (M9), the merged record's email inbox when no one holds the phone, the phone leg first (M10), both
--      screens (M11); a customer made after the booking (M4).
--   C  Came by a purchase at the Adelphi centre that day (the Owner, 29 Oct 2026): paid, partially paid,
--      FOC, refund requested and refunded count; draft, unpaid, cancellation requested and cancelled do
--      not; nor the Van & RoadShow, an online (web) order, a VIP order or an event guest's invoice; the
--      business date, else the Singapore date it was made; another day, a deleted invoice and none: miss;
--      a survey that day still counts; Visited and First visit are as they were; both screens.
--   S  States: upcoming (today and later; today's until the day is over), came, miss (only after the day
--      ends), none, cancelled-only = none, the next beats the last; on the state rule with a given day.
--   R  Both functions' rows, Tier 1 and Tier 2: booking_at and booking_state, as the state rule says; every
--      other key and value and the row order as before 480 (when this file installs it); the portal's
--      rows carry no phone, email, uid or answer of the booking.
--   P  Who: the Downline for Owners, Admins, Managers and Staff (the same answer), refused to an
--      Inventory Manager, a deactivated employee, a login that is not staff, an affiliate and signed out;
--      the portal for the affiliate's own network only; ingest, backfill, the matching and the state rule
--      for the service role alone, apply and parse_time for no client at all; the table read by the
--      service role alone and written by no client.
--   G  The md5s, grants and the table's shape after 480.
--   N  480 twice changes nothing; its first run changes the two functions and adds the six (no other);
--      its self-test leaves no row; a function changed since (or a table of another shape) is refused,
--      nothing changed; so is a database whose Adelphi store is renamed or deleted (N8).
--
-- Disposable local database only (a copy of production as it is: run it on 478's copy, where it installs
-- 480 twice, or with -v skip_install=1 where 480 is already in); everything is rolled back. A copy without
-- production's stores gets made-up RETAIL-ADELPHI and ADELPHI-VAN stores for the run. Every name and email is
-- invented (@example.com / @example.invalid; Gmail addresses with made-up local parts); phones are ACMA's
-- fictional range (+61 2 5550 ....), found free at run time. Every check runs, then the file fails if any did.
--   psql -X -v ON_ERROR_STOP=1 [-v skip_install=1] -f scripts/referrals/tests/downline-booking-480.sql
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
-- Run q as a login (a fixture key), 'anon' (signed out), 'service' (the service role) or 'server' (no
-- request at all), through the API's own database role, as the pages and the Edge Function do: 'ok', a
-- tab and the answer, or the SQLSTATE, a tab and the message.
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
$$ select 'cb480-' || lower(tag) || '-' || pg_temp.tx('sfx') || '@example.invalid' $$;
create function pg_temp.ph(n int) returns text language sql as
$$ select '+6125550' || lpad((pg_temp.tx('phbase')::int + n)::text, 4, '0') $$;
-- A moment as cal.com writes it (UTC, milliseconds, Z), and a Singapore day and time as a moment.
create function pg_temp.iso(t timestamptz) returns text language sql as
$$ select to_char(t at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') $$;
create function pg_temp.sg(d date, t time) returns timestamptz language sql as $$ select (d + t) at time zone 'Asia/Singapore' $$;
create function pg_temp.today() returns date language sql as $$ select (now() at time zone 'Asia/Singapore')::date $$;
create function pg_temp.uid(tag text) returns text language sql as $$ select 'cb480' || pg_temp.tx('sfx') || tag $$;
-- A cal.com webhook body: a booking (with a name, a note and a location that must not be stored), and one event.
create function pg_temp.bk(tag text, start timestamptz, phone text, email text, extra jsonb default '{}') returns jsonb language sql as
$$ select jsonb_build_object('uid', pg_temp.uid(tag), 'title', 'Fixture booking ' || tag, 'type', 'free', 'eventTypeId', 1001,
          'startTime', pg_temp.iso(start), 'endTime', pg_temp.iso(start + interval '1 hour'), 'location', 'Fixture Centre',
          'status', 'ACCEPTED', 'additionalNotes', 'fixture note ' || tag,
          'responses', jsonb_build_object('name', jsonb_build_object('label', 'Your name', 'value', 'Fixture Person ' || tag),
                                          'email', jsonb_build_object('label', 'Email', 'value', email),
                                          'WhatsApp-Number', jsonb_build_object('label', 'WhatsApp Number', 'value', phone),
                                          'notes', jsonb_build_object('label', 'Notes', 'value', 'fixture answer ' || tag)),
          'attendees', jsonb_build_array(jsonb_build_object('name', 'Fixture Person ' || tag, 'email', email, 'timeZone', 'Asia/Singapore')))
          || extra $$;
create function pg_temp.ev(trig text, at timestamptz, payload jsonb) returns jsonb language sql as
$$ select jsonb_build_object('triggerEvent', trig, 'createdAt', pg_temp.iso(at), 'payload', payload) $$;
create function pg_temp.err(q text) returns text language plpgsql as
$$begin execute q; return 'ok'; exception when others then return sqlstate || ' ' || sqlerrm; end$$;
-- A row of a downline or a portal answer, by name, without its two new keys; and the two new keys.
create function pg_temp.rows_by(j jsonb, tier text, namekey text) returns jsonb language sql as
$$ select coalesce(jsonb_object_agg(r ->> namekey, jsonb_build_array(r ->> 'booking_state', r ->> 'booking_at')), '{}'::jsonb)
     from jsonb_array_elements(j -> tier) r $$;

-- ═════ Fixture: logins, a store, the network and the matching cases (as the server, no request) ═════
set local client_min_messages = warning;
do $$
declare k text; v uuid; st uuid; r uuid; a2 uuid; aff uuid; used boolean; gone text[];
begin
  perform set_config('request.jwt.claims', '', true);
  -- Letters only, so no run of digits in a uid or an id can be read as a phone number.
  perform pg_temp.put('sfx', translate(lower(substr(md5(gen_random_uuid()::text), 1, 8)), '0123456789', 'ghijklmnop'));
  -- Two hundred free fictional phones in a row (+61 2 5550 nnnn): no customer's, in use (a range scan of the partial
  -- phone index, so a copy with production's customers is quick) or deleted (their phones read once: a merged
  -- record's booking follows the merge), and no active booking's where 480 is in.
  gone := array(select public.normalize_customer_phone(c.phone) from public.customers c where c.deleted_at is not null);
  for g in 1000 .. 9600 by 200 loop
    continue when exists (select 1 from public.customers c
                           where c.deleted_at is null and public.normalize_customer_phone(c.phone)
                                 between '+6125550' || lpad(g::text, 4, '0') and '+6125550' || lpad((g + 199)::text, 4, '0'));
    continue when exists (select 1 from unnest(gone) x(ph)
                           where x.ph between '+6125550' || lpad(g::text, 4, '0') and '+6125550' || lpad((g + 199)::text, 4, '0'));
    if to_regclass('public.calcom_bookings') is not null then
      execute format('select exists (select 1 from public.calcom_bookings b where b.status = ''active'' and b.phone_key between %L and %L)',
                     '+6125550' || lpad(g::text, 4, '0'), '+6125550' || lpad((g + 199)::text, 4, '0')) into used;
      continue when used;
    end if;
    perform pg_temp.put('phbase', g::text);
    exit;
  end loop;
  if pg_temp.tx('phbase') is null then raise exception 'no free fictional phones'; end if;
  foreach k in array array['owner', 'admin', 'manager', 'invman', 'staff', 'inactive', 'nostaff', 'aff', 'aff2', 'aff3', 'aff4'] loop
    insert into auth.users (id, email) values (gen_random_uuid(), pg_temp.mail(k)) returning id into v;
    perform pg_temp.putx(k, v);
  end loop;
  insert into public.profiles (id, full_name, email, role, is_active, invitation_status)
  select pg_temp.fx(x.k), 'Test ' || x.k, pg_temp.mail(x.k), x.role::public.user_role, x.active, 'accepted'
    from (values ('owner', 'owner', true), ('admin', 'admin', true), ('manager', 'manager', true),
                 ('invman', 'inventory_manager', true), ('staff', 'staff', true), ('inactive', 'staff', false)) x(k, role, active);
  insert into public.stores (name, code, country_code) values ('Test Store 480 ' || pg_temp.tx('sfx'), 'T480' || pg_temp.tx('sfx'), 'SG')
    returning id into st;
  insert into public.user_store_assignments (user_id, store_id)
  select pg_temp.fx(x.k), st from unnest(array['manager', 'invman', 'staff', 'inactive']) x(k);
  -- The Adelphi centre and the Van & RoadShow, by their codes as production has them (480 refuses without the
  -- first); a copy without production's stores gets made-up ones for this run.
  insert into public.stores (name, code, country_code) values ('T480 Adelphi centre', 'RETAIL-ADELPHI', 'SG'),
                                                              ('T480 Van and RoadShow', 'ADELPHI-VAN', 'SG')
    on conflict (code) do nothing;
  perform pg_temp.putx('adelphi', (select s.id from public.stores s where s.code = 'RETAIL-ADELPHI'));
  perform pg_temp.putx('van', (select s.id from public.stores s where s.code = 'ADELPHI-VAN'));

  -- The referrer (an affiliate with a portal login) and their network.
  insert into public.customers (full_name, phone, email) values ('T480 Referrer Rae', pg_temp.ph(0), pg_temp.mail('rae')) returning id into r;
  perform pg_temp.putx('rae', r);
  insert into public.customer_affiliates (customer_id, status, store_id, activated_at) values (r, 'active', st, now()) returning id into aff;
  insert into public.affiliate_accounts (auth_user_id, customer_id, affiliate_id, status) values (pg_temp.fx('aff'), r, aff, 'claimed');
  -- Tier 1: upcoming (with an older missed booking too), today, came, missed, none, cancelled only, rescheduled away only.
  foreach k in array array['u1', 't1', 'c1', 'm1', 'n1', 'x1', 'r1'] loop
    insert into public.customers (full_name, phone, email, referred_by)
    values ('T480 Tier1 ' || k, pg_temp.ph(1 + array_position(array['u1', 't1', 'c1', 'm1', 'n1', 'x1', 'r1'], k)), pg_temp.mail(k), r)
    returning id into v;
    perform pg_temp.putx(k, v);
  end loop;
  -- Tier 2, under u1: upcoming, came, missed, none.
  foreach k in array array['u2', 'c2', 'm2', 'n2'] loop
    insert into public.customers (full_name, phone, email, referred_by)
    values ('T480 Tier2 ' || k, pg_temp.ph(10 + array_position(array['u2', 'c2', 'm2', 'n2'], k)), pg_temp.mail(k), pg_temp.fx('u1'))
    returning id into v;
    perform pg_temp.putx(k, v);
  end loop;
  -- A second affiliate and their one friend.
  insert into public.customers (full_name, phone) values ('T480 Other Affiliate', pg_temp.ph(20)) returning id into a2;
  perform pg_temp.putx('a2', a2);
  insert into public.customer_affiliates (customer_id, status, store_id, activated_at) values (a2, 'active', st, now()) returning id into aff;
  insert into public.affiliate_accounts (auth_user_id, customer_id, affiliate_id, status) values (pg_temp.fx('aff2'), a2, aff, 'claimed');
  insert into public.customers (full_name, phone, referred_by) values ('T480 Other Friend', pg_temp.ph(21), a2) returning id into v;
  perform pg_temp.putx('o1', v);

  -- The matching cases (no referrer).
  insert into public.customers (full_name, phone, email) values ('T480 Shared One', pg_temp.ph(30), 't480.shared.one' || pg_temp.tx('sfx') || '@gmail.com')
    returning id into v; perform pg_temp.putx('s1', v);
  insert into public.customers (full_name, phone, email) values ('T480 Shared Two', pg_temp.ph(30), pg_temp.mail('s2'))
    returning id into v; perform pg_temp.putx('s2', v);
  insert into public.customers (full_name, phone, email) values ('T480 Email Only', pg_temp.ph(31), pg_temp.mail('e1'))
    returning id into v; perform pg_temp.putx('e1', v);
  insert into public.customers (full_name, phone, email) values ('T480 Same Mail A', pg_temp.ph(32), pg_temp.mail('qq'))
    returning id into v; perform pg_temp.putx('q1', v);
  insert into public.customers (full_name, phone, email) values ('T480 Same Mail B', pg_temp.ph(33), upper(pg_temp.mail('qq')))
    returning id into v; perform pg_temp.putx('q2', v);
  insert into public.customers (full_name, phone) values ('T480 Deleted', pg_temp.ph(34)) returning id into v; perform pg_temp.putx('d1', v);
  insert into public.customers (full_name, phone) values ('T480 Living', pg_temp.ph(34)) returning id into v; perform pg_temp.putx('d2', v);
  insert into public.customers (full_name, phone) values ('T480 Deleted Alone', pg_temp.ph(35)) returning id into v; perform pg_temp.putx('d3', v);
  update public.customers set deleted_at = now() where id in (pg_temp.fx('d1'), pg_temp.fx('d3'));
  insert into public.customers (full_name, phone) values ('T480 Twin Kept', pg_temp.ph(36)) returning id into v; perform pg_temp.putx('g1', v);
  insert into public.customers (full_name, phone) values ('T480 Twin Merged', pg_temp.ph(36)) returning id into v; perform pg_temp.putx('g2', v);
  insert into public.customers (full_name, phone) values ('T480 Day Missed', pg_temp.ph(40)) returning id into v; perform pg_temp.putx('k1', v);
  insert into public.customers (full_name, phone) values ('T480 Day Came', pg_temp.ph(41)) returning id into v; perform pg_temp.putx('k2', v);

  -- Visits (the consultant's survey with an answer, dated the Singapore day it was made): c1 and c2 two
  -- days ago (their booking days), k2 on its booking day; m1 visited on another day (the day before its booking).
  insert into public.health_surveys (survey_no, customer_id, full_name, phone, source, submitted_at, remarks_condition)
  select 'HS-T480-' || pg_temp.tx('sfx') || '-' || x.k, pg_temp.fx(x.k), 'T480 ' || x.k, '+61255500000', 'consultant', x.at, 'T480 answer'
    from (values ('c1', pg_temp.sg(pg_temp.today() - 2, '15:00')), ('c2', pg_temp.sg(pg_temp.today() - 2, '23:30')),
                 ('k2', pg_temp.sg(pg_temp.today() + 20, '10:00')), ('m1', pg_temp.sg(pg_temp.today() - 3, '11:00'))) x(k, at);
end $$;
set local client_min_messages = notice;

-- What the two screens answered before 480 (only when this file installs it), as the Manager and as the affiliate.
\if :{?skip_install}
\else
select pg_temp.put('pre_dl', pg_temp.try_as('manager', format('select public.customer_downline_visits(%L::uuid)::text', pg_temp.fx('rae'))));
select pg_temp.put('pre_net', pg_temp.try_as('aff', 'select public.affiliate_portal_network()::text'));
create temp table b480 as select * from pg_temp.fn_md5s();
create temp table r480 as select pg_temp.row_counts() as before, pg_temp.seqs() as seq_before;
\ir ../../../supabase/480_downline_and_network_show_calcom_booking.sql
create temp table m480 as select * from pg_temp.fn_md5s();
alter table r480 add column after1 jsonb, add column seq_after1 jsonb;
update r480 set after1 = pg_temp.row_counts(), seq_after1 = pg_temp.seqs();
\ir ../../../supabase/480_downline_and_network_show_calcom_booking.sql
create temp table m480b as select * from pg_temp.fn_md5s();
\endif

-- Helpers that read 480's own objects (made once 480 is in).
create function pg_temp.ingest(j jsonb) returns text language sql as $$ select public.calcom_booking_ingest(j)->>'result' $$;
create function pg_temp.row(tag text) returns public.calcom_bookings language sql as
$$ select * from public.calcom_bookings where uid = pg_temp.uid(tag) $$;
-- One customer's booking and state by the state rule (p_today: a given Singapore day, or today).
create function pg_temp.st(key text, d date default null) returns text language sql as
$$ select b.booking_state || coalesce(' ' || pg_temp.iso(b.booking_at), '')
     from public.calcom_customer_bookings(array[pg_temp.fx(key)], d) b $$;
create function pg_temp.st0(key text, d date default null) returns text language sql as
$$ select b.booking_state from public.calcom_customer_bookings(array[pg_temp.fx(key)], d) b $$;

-- ═════ I Ingest ═════
-- I1 created: what is kept, and only that.
select pg_temp.put('i1', pg_temp.ingest(pg_temp.ev('BOOKING_CREATED', now() - interval '2 days',
  pg_temp.bk('i1', pg_temp.sg(pg_temp.today() + 5, '14:00'), '+61 2 5550 ' || substr(pg_temp.ph(50), 9), ' ' || upper(pg_temp.mail('i1')) || ' '))));
select pg_temp.check(pg_temp.tx('i1') = 'created'
    and (select (r.status, r.start_at, r.end_at, r.event_type_id, r.event_type_slug, r.phone_key, r.email_key, r.source, r.last_trigger, r.rescheduled_to)
                is not distinct from ('active'::text, pg_temp.sg(pg_temp.today() + 5, '14:00'), pg_temp.sg(pg_temp.today() + 5, '15:00'), 1001::bigint, 'free'::text,
                   pg_temp.ph(50), pg_temp.mail('i1'), 'webhook'::text, 'BOOKING_CREATED'::text, null::text)
           from pg_temp.row('i1') r)
    and (select date_trunc('milliseconds', r.last_event_at) = date_trunc('milliseconds', now() - interval '2 days') from pg_temp.row('i1') r),
  'I1 BOOKING_CREATED stores the uid, start, end, event type, the WhatsApp-Number as normalize_customer_phone reads it, the email inbox, webhook and the event''s time');
select pg_temp.check((select array_agg(a.attname::text order by a.attnum) from pg_attribute a
                       where a.attrelid = 'public.calcom_bookings'::regclass and a.attnum > 0 and not a.attisdropped)
    = array['uid', 'start_at', 'end_at', 'status', 'rescheduled_to', 'event_type_id', 'event_type_slug', 'phone_key', 'email_key',
            'source', 'last_event_at', 'last_trigger', 'created_at', 'updated_at']
    and (select count(*) from public.calcom_bookings b where b::text ~* 'fixture') = 0,
  'I2 nothing else is kept: no name, answer, note, title or location (no column for one, and no row holds the fixture''s words)');
-- I3 the same event again: nothing changes, not even updated_at.
select pg_temp.put('i1_row', (select row(r.*)::text from pg_temp.row('i1') r));
select pg_temp.put('i3', pg_temp.ingest(pg_temp.ev('BOOKING_CREATED', now() - interval '2 days',
  pg_temp.bk('i1', pg_temp.sg(pg_temp.today() + 5, '14:00'), pg_temp.ph(50), pg_temp.mail('i1')))));
select pg_temp.check(pg_temp.tx('i3') = 'unchanged' and (select row(r.*)::text from pg_temp.row('i1') r) = pg_temp.tx('i1_row'),
  'I3 the same event sent again changes nothing (unchanged, the row word for word)');
-- I4 an older event (a cancellation from before the creation): stale, still active.
select pg_temp.check(pg_temp.ingest(pg_temp.ev('BOOKING_CANCELLED', now() - interval '3 days', jsonb_build_object('uid', pg_temp.uid('i1')))) = 'stale'
    and (select status from pg_temp.row('i1')) = 'active' and (select row(r.*)::text from pg_temp.row('i1') r) = pg_temp.tx('i1_row'),
  'I4 an event older than the last one applied changes nothing (stale): a late cancellation from before does not cancel');
-- I5 rescheduled to a new uid (rescheduleUid): the new one active, the old one rescheduled away.
select pg_temp.put('i5', (public.calcom_booking_ingest(pg_temp.ev('BOOKING_RESCHEDULED', now() - interval '1 day',
  pg_temp.bk('i5', pg_temp.sg(pg_temp.today() + 6, '10:00'), pg_temp.ph(50), pg_temp.mail('i1'),
             jsonb_build_object('rescheduleUid', pg_temp.uid('i1'), 'rescheduleStartTime', pg_temp.iso(pg_temp.sg(pg_temp.today() + 5, '14:00'))))))::text));
select pg_temp.check(pg_temp.tx('i5')::jsonb = '{"result": "created", "previous": "updated"}'
    and (select (status, rescheduled_to, phone_key, email_key, last_trigger) is not distinct from ('rescheduled'::text, pg_temp.uid('i5'), null::text, null::text, 'BOOKING_RESCHEDULED'::text)
           from pg_temp.row('i1'))
    and (select (status, start_at, phone_key) is not distinct from ('active'::text, pg_temp.sg(pg_temp.today() + 6, '10:00'), pg_temp.ph(50)) from pg_temp.row('i5')),
  'I5 BOOKING_RESCHEDULED with rescheduleUid: the new uid is the booking (active), the old one rescheduled away (and keeps no phone or email): ' || pg_temp.tx('i5'));
-- I6 the same with fromReschedule, the old uid never seen: kept as rescheduled; its late CREATED cannot bring it back.
select pg_temp.put('i6', (public.calcom_booking_ingest(pg_temp.ev('BOOKING_RESCHEDULED', now() - interval '20 hours',
  pg_temp.bk('i6', pg_temp.sg(pg_temp.today() + 7, '10:00'), pg_temp.ph(51), null, jsonb_build_object('fromReschedule', pg_temp.uid('i6old')))))::text));
select pg_temp.check(pg_temp.tx('i6')::jsonb = '{"result": "created", "previous": "created"}'
    and (select (status, rescheduled_to, start_at) is not distinct from ('rescheduled'::text, pg_temp.uid('i6'), null::timestamptz) from pg_temp.row('i6old'))
    and pg_temp.ingest(pg_temp.ev('BOOKING_CREATED', now() - interval '30 hours',
          pg_temp.bk('i6old', pg_temp.sg(pg_temp.today() + 6, '09:00'), pg_temp.ph(51), null))) = 'stale'
    and pg_temp.ingest(pg_temp.ev('BOOKING_CREATED', now() - interval '10 hours',
          pg_temp.bk('i6old', pg_temp.sg(pg_temp.today() + 6, '09:00'), pg_temp.ph(51), null))) = 'unchanged'
    and (select status from pg_temp.row('i6old')) = 'rescheduled',
  'I6 BOOKING_RESCHEDULED with fromReschedule and an old uid never seen: kept as rescheduled away; its CREATED arriving late (older, or even newer) leaves it so');
-- I7 rescheduled under the same uid: the booking moves.
select pg_temp.check(pg_temp.ingest(pg_temp.ev('BOOKING_RESCHEDULED', now() - interval '10 hours',
          pg_temp.bk('i5', pg_temp.sg(pg_temp.today() + 8, '16:00'), pg_temp.ph(50), pg_temp.mail('i1'), jsonb_build_object('rescheduleUid', pg_temp.uid('i5'))))) = 'updated'
    and pg_temp.ingest(pg_temp.ev('BOOKING_RESCHEDULED', now() - interval '9 hours',
          pg_temp.bk('i5', pg_temp.sg(pg_temp.today() + 9, '16:00'), pg_temp.ph(50), pg_temp.mail('i1')))) = 'updated'
    and (select (status, start_at, end_at) is not distinct from ('active'::text, pg_temp.sg(pg_temp.today() + 9, '16:00'), pg_temp.sg(pg_temp.today() + 9, '17:00'))
           from pg_temp.row('i5')),
  'I7 BOOKING_RESCHEDULED under the same uid (rescheduleUid itself, or none): the booking moves to the new time');
-- I8 cancelled, also a uid never seen; a late CREATED cannot bring it back.
select pg_temp.check(pg_temp.ingest(pg_temp.ev('BOOKING_CANCELLED', now() - interval '8 hours',
          jsonb_build_object('uid', pg_temp.uid('i5'), 'startTime', pg_temp.iso(pg_temp.sg(pg_temp.today() + 9, '16:00'))))) = 'updated'
    and (select (status, phone_key, email_key) is not distinct from ('cancelled'::text, null::text, null::text) from pg_temp.row('i5'))
    and pg_temp.ingest(pg_temp.ev('BOOKING_CANCELLED', now() - interval '8 hours', jsonb_build_object('uid', pg_temp.uid('i8')))) = 'created'
    and (select (status, start_at, source) is not distinct from ('cancelled'::text, null::timestamptz, 'webhook'::text) from pg_temp.row('i8'))
    and pg_temp.ingest(pg_temp.ev('BOOKING_CREATED', now() - interval '9 hours', pg_temp.bk('i8', pg_temp.sg(pg_temp.today() + 3, '10:00'), pg_temp.ph(52), null))) = 'stale'
    and pg_temp.ingest(pg_temp.ev('BOOKING_CREATED', now() - interval '7 hours', pg_temp.bk('i8', pg_temp.sg(pg_temp.today() + 3, '10:00'), pg_temp.ph(52), null))) = 'unchanged'
    and (select status from pg_temp.row('i8')) = 'cancelled',
  'I8 BOOKING_CANCELLED cancels (keeping no phone or email); a uid never seen is stored cancelled, and its CREATED arriving late leaves it cancelled');
-- I9 a cancellation at the very moment of the creation wins; a creation at the moment of a cancellation does not.
select pg_temp.put('i9_at', pg_temp.iso(now() - interval '6 hours'));
select pg_temp.check(public.calcom_booking_ingest(jsonb_build_object('triggerEvent', 'BOOKING_CREATED', 'createdAt', pg_temp.tx('i9_at'),
          'payload', pg_temp.bk('i9', pg_temp.sg(pg_temp.today() + 3, '10:00'), pg_temp.ph(53), null)))->>'result' = 'created'
    and public.calcom_booking_ingest(jsonb_build_object('triggerEvent', 'BOOKING_CANCELLED', 'createdAt', pg_temp.tx('i9_at'),
          'payload', jsonb_build_object('uid', pg_temp.uid('i9'))))->>'result' = 'updated'
    and public.calcom_booking_ingest(jsonb_build_object('triggerEvent', 'BOOKING_CREATED', 'createdAt', pg_temp.tx('i9_at'),
          'payload', pg_temp.bk('i9', pg_temp.sg(pg_temp.today() + 3, '10:00'), pg_temp.ph(53), null)))->>'result' = 'stale'
    and (select status from pg_temp.row('i9')) = 'cancelled',
  'I9 the same moment: a cancellation after a creation applies; a creation after a cancellation does not');
-- I10 triggers that are not read: ignored, nothing stored.
select pg_temp.put('i10_n', (select count(*)::text from public.calcom_bookings));
select pg_temp.check((select array_agg(public.calcom_booking_ingest(pg_temp.ev(t, now(), pg_temp.bk('i10' || lower(t), pg_temp.sg(pg_temp.today() + 3, '10:00'), pg_temp.ph(54), null)))->>'result' order by t)
                        from unnest(array['PING', 'BOOKING_REJECTED', 'BOOKING_REQUESTED', 'MEETING_ENDED', 'BOOKING_NO_SHOW_UPDATED', 'booking_created']) t)
                     = array_fill('ignored'::text, array[6])
    and (select count(*)::text from public.calcom_bookings) = pg_temp.tx('i10_n'),
  'I10 PING, BOOKING_REJECTED, BOOKING_REQUESTED, MEETING_ENDED, BOOKING_NO_SHOW_UPDATED and a lower-case trigger are ignored, nothing stored');
-- I11 the phone: WhatsApp-Number; when it gives no number, the attendee's phone, then smsReminderNumber; the email: the answer, else the attendee's.
select pg_temp.check(pg_temp.ingest(pg_temp.ev('BOOKING_CREATED', now(), jsonb_build_object('uid', pg_temp.uid('i11a'), 'startTime', pg_temp.iso(pg_temp.sg(pg_temp.today() + 3, '10:00')),
          'responses', jsonb_build_object('WhatsApp-Number', 'not a number', 'smsReminderNumber', jsonb_build_object('value', pg_temp.ph(56))),
          'attendees', jsonb_build_array(jsonb_build_object('phoneNumber', pg_temp.ph(55), 'email', pg_temp.mail('i11a')))))) = 'created'
    and (select (phone_key, email_key) is not distinct from (pg_temp.ph(55), pg_temp.mail('i11a')) from pg_temp.row('i11a'))
    and pg_temp.ingest(pg_temp.ev('BOOKING_CREATED', now(), jsonb_build_object('uid', pg_temp.uid('i11b'), 'startTime', pg_temp.iso(pg_temp.sg(pg_temp.today() + 3, '10:00')),
          'responses', jsonb_build_object('smsReminderNumber', jsonb_build_object('value', pg_temp.ph(56)), 'email', pg_temp.mail('i11b')),
          'attendees', jsonb_build_array(jsonb_build_object('email', pg_temp.mail('other')))))) = 'created'
    and (select (phone_key, email_key) is not distinct from (pg_temp.ph(56), pg_temp.mail('i11b')) from pg_temp.row('i11b'))
    and pg_temp.ingest(pg_temp.ev('BOOKING_CREATED', now(), jsonb_build_object('uid', pg_temp.uid('i11c'), 'startTime', pg_temp.iso(pg_temp.sg(pg_temp.today() + 3, '10:00')),
          'responses', jsonb_build_object('WhatsApp-Number', pg_temp.ph(57), 'smsReminderNumber', pg_temp.ph(58)),
          'attendees', jsonb_build_array(jsonb_build_object('phoneNumber', pg_temp.ph(59)))))) = 'created'
    and (select (phone_key, email_key) is not distinct from (pg_temp.ph(57), null::text) from pg_temp.row('i11c')),
  'I11 the phone is the WhatsApp-Number answer, else the attendee''s phone, else the smsReminderNumber answer; the email the answer, else the attendee''s');
-- I12 malformed: 22023 naming the field, never quoting a value.
select pg_temp.put('i12', (select string_agg(x.k || '=' || pg_temp.err(format('select public.calcom_booking_ingest(%L::jsonb)', x.j)), ' | ' order by x.k)
  from (values
    ('a', '"just text"'), ('b', '{"createdAt":"2026-10-29T00:00:00Z","payload":{"uid":"cb480x"}}'),
    ('c', '{"triggerEvent":"BOOKING_CREATED","createdAt":"2026-10-29T00:00:00Z"}'),
    ('d', '{"triggerEvent":"BOOKING_CREATED","payload":{"uid":"bad uid +61255509999","startTime":"2026-11-01T06:00:00Z"}}'),
    ('e', '{"triggerEvent":"BOOKING_CREATED","payload":{"uid":"cb480x"}}'),
    ('f', '{"triggerEvent":"BOOKING_CREATED","payload":{"uid":"cb480x","startTime":"now"}}'),
    ('g', '{"triggerEvent":"BOOKING_CREATED","payload":{"uid":"cb480x","startTime":"2026-13-45T06:00:00Z"}}'),
    ('h', '{"triggerEvent":"BOOKING_CREATED","payload":{"uid":"cb480x","startTime":"2026-11-01 14:00"}}'),
    ('i', '{"triggerEvent":"BOOKING_CREATED","createdAt":"yesterday","payload":{"uid":"cb480x","startTime":"2026-11-01T06:00:00Z"}}'),
    ('j', '{"triggerEvent":"BOOKING_CREATED","createdAt":"2099-01-01T00:00:00Z","payload":{"uid":"cb480x","startTime":"2026-11-01T06:00:00Z"}}'),
    ('k', '{"triggerEvent":"BOOKING_RESCHEDULED","payload":{"uid":"cb480x","rescheduleUid":"x@fixture.example.invalid","startTime":"2026-11-01T06:00:00Z"}}'),
    ('l', '{"triggerEvent":"BOOKING_CREATED","payload":{"uid":"gcal:abc","startTime":"2026-11-01T06:00:00Z"}}'),
    ('m', '{"triggerEvent":42,"payload":{"uid":"cb480x"}}'),
    ('n', '{"triggerEvent":"BOOKING_CREATED","payload":"cb480x"}')) x(k, j)));
select pg_temp.check(pg_temp.tx('i12') = concat_ws(' | ',
      'a=22023 calcom_booking_ingest: the event is not a JSON object',
      'b=22023 calcom_booking_ingest: triggerEvent is missing',
      'c=22023 calcom_booking_ingest: payload is missing',
      'd=22023 calcom_booking_ingest: payload.uid is missing or not a booking uid',
      'e=22023 calcom_booking_ingest: payload.startTime is missing',
      'f=22023 calcom_booking_ingest: payload.startTime is not a moment',
      'g=22023 calcom_booking_ingest: payload.startTime is not a moment',
      'h=22023 calcom_booking_ingest: payload.startTime is not a moment',
      'i=22023 calcom_booking_ingest: createdAt is not a moment',
      'j=22023 calcom_booking_ingest: createdAt is more than a day ahead',
      'k=22023 calcom_booking_ingest: payload.rescheduleUid is not a booking uid',
      'l=22023 calcom_booking_ingest: payload.uid is missing or not a booking uid',
      'm=22023 calcom_booking_ingest: triggerEvent is missing',
      'n=22023 calcom_booking_ingest: payload is missing')
    and (select count(*) from public.calcom_bookings where uid = 'cb480x') = 0,
  'I12 malformed bodies are refused with 22023 and a message naming the field, never quoting a value: ' || pg_temp.tx('i12'));

-- ═════ B Calendar fill and monthly catch-up (one call) ═════
-- ONE window, from 300 to 360 days ahead (no other check's booking is there), listed as the Calendar connector
-- gives events: id, summary, description, start/end {dateTime, timeZone}, status, updated (and fields not read).
select pg_temp.put('wfrom', pg_temp.sg(pg_temp.today() + 300, '00:00')::text);
select pg_temp.put('wto', pg_temp.sg(pg_temp.today() + 360, '00:00')::text);
create function pg_temp.gt(t timestamptz) returns jsonb language sql as
$$ select jsonb_build_object('dateTime', to_char(t at time zone 'Asia/Singapore', 'YYYY-MM-DD"T"HH24:MI:SS') || '+08:00', 'timeZone', 'Asia/Singapore') $$;
create function pg_temp.gev(id text, summary text, descr text, start timestamptz, status text default 'confirmed', upd timestamptz default null)
  returns jsonb language sql as
$$ select jsonb_strip_nulls(jsonb_build_object('id', id, 'summary', summary, 'description', descr, 'status', status,
          'start', pg_temp.gt(start), 'end', pg_temp.gt(start + interval '1 hour'),
          'updated', pg_temp.iso(coalesce(upd, now() - interval '1 hour')),
          'colorId', '11', 'attendees', jsonb_build_array(jsonb_build_object('email', 'fixture@example.invalid')))) $$;
create function pg_temp.link(tag text) returns text language sql as
$$ select 'What: Fixture' || chr(10) || 'Need to make a change? Cancel or reschedule: https://app.cal.com/booking/' || pg_temp.uid(tag) || '?changes=true' $$;
-- The window above, listed when this transaction began (now()) unless told otherwise; a dry run unless told otherwise;
-- cancel: the uids a real run may cancel when they are missing (the Owner's, from the dry run).
create function pg_temp.fill(ev jsonb, dry boolean default true, cancel text[] default null, incl boolean default false,
                             listed timestamptz default null) returns jsonb language sql as
$$ select public.calcom_booking_backfill(ev, pg_temp.tx('wfrom')::timestamptz, pg_temp.tx('wto')::timestamptz,
                                         coalesce(listed, now()), dry, cancel, incl) $$;
-- The counts alone; the changes as "change tag old new" (the uid without this run's prefix; times in Singapore).
create function pg_temp.counts(j jsonb) returns jsonb language sql as $$ select j - 'changes' $$;
create function pg_temp.changes(j jsonb) returns text language sql as
$$ select coalesce(string_agg(format('%s %s %s %s', c ->> 'change', replace(c ->> 'uid', 'cb480' || pg_temp.tx('sfx'), ''),
                                     coalesce(c ->> 'old_start', '-'), coalesce(c ->> 'new_start', '-')), ' | ' order by n), '')
     from jsonb_array_elements(j -> 'changes') with ordinality x(c, n) $$;
create function pg_temp.changes_nm(j jsonb) returns text language sql as
$$ select pg_temp.changes(jsonb_build_object('changes', (select coalesce(jsonb_agg(c order by n), '[]'::jsonb)
                                                          from jsonb_array_elements(j -> 'changes') with ordinality x(c, n)
                                                         where c ->> 'change' not in ('missing_from_calendar', 'cancelled_missing')))) $$;
create function pg_temp.sgs(t timestamptz) returns text language sql as
$$ select to_char(t at time zone 'Asia/Singapore', 'YYYY-MM-DD"T"HH24:MI:SS"+08:00"') $$;
create function pg_temp.d(n int) returns text language sql as $$ select to_char(pg_temp.today() + n, 'YYYY-MM-DD') $$;
create function pg_temp.rows_text(tags text[]) returns text language sql as
$$ select string_agg(row(b.*)::text, chr(10) order by b.uid) from public.calcom_bookings b where b.uid = any (array(select pg_temp.uid(t) from unnest(tags) t)) $$;

-- The webhook stored these two days ago, in the window: one the calendar shows as it is (wb1), one the calendar
-- shows moved by a later edit (wb2), one whose calendar copy is older than the webhook's event (wb3), one the
-- calendar no longer carries (wm1); outside the window and not in the listing (wo1); stored after the listing
-- began (wl1: its last change a minute after this transaction's start, when the listing is taken to begin).
select pg_temp.ingest(pg_temp.ev('BOOKING_CREATED', now() - interval '2 days', pg_temp.bk(x.tag, pg_temp.sg(pg_temp.today() + x.d, '10:00'), pg_temp.ph(x.n), null)))
  from (values ('wb1', 313, 140), ('wb2', 314, 141), ('wb3', 315, 142), ('wm1', 316, 143), ('wo1', 380, 144), ('wl1', 317, 145)) x(tag, d, n);
update public.calcom_bookings set updated_at = now() + interval '1 minute' where uid = pg_temp.uid('wl1');
select pg_temp.put('fill', jsonb_build_array(
  -- a cal.com booking staff marked Cxl (a no-show): still a booking
  pg_temp.gev('cb480ga' || pg_temp.tx('sfx'), 'Cxl (Fixture Aff) Fixture Person ' || pg_temp.ph(60) || ' Fixture Centre Free Fixture Bundle',
              pg_temp.link('ga'), pg_temp.sg(pg_temp.today() + 310, '14:00')),
  -- the same booking again (a second copy, updated earlier): the copy updated last counts
  pg_temp.gev('cb480gb' || pg_temp.tx('sfx'), 'Fixture Person ' || pg_temp.ph(61), pg_temp.link('ga'), pg_temp.sg(pg_temp.today() + 311, '14:00'),
              'confirmed', now() - interval '3 hours'),
  -- listed cancelled (should a source ever list one): kept as cancelled
  pg_temp.gev('cb480gc' || pg_temp.tx('sfx'), 'Fixture Person ' || pg_temp.ph(62), pg_temp.link('gc'), pg_temp.sg(pg_temp.today() + 312, '14:00'), 'cancelled'),
  -- a reschedule link (cal.com's own host); a title starting with the number
  pg_temp.gev('cb480gd' || pg_temp.tx('sfx'), pg_temp.ph(63) || ' Fixture Person Fixture Centre',
              'Reschedule: https://cal.com/reschedule/' || pg_temp.uid('gd'), pg_temp.sg(pg_temp.today() + 312, '11:00')),
  -- typed by hand: no cal.com link
  pg_temp.gev('cb480ge' || pg_temp.tx('sfx'), '(Fixture) Hand Typed ' || pg_temp.ph(64) || ' - 3in1', 'typed by staff', pg_temp.sg(pg_temp.today() + 313, '14:00')),
  -- no number in the title (only in the description, which is read for the uid alone): a new booking is skipped
  pg_temp.gev('cb480gf' || pg_temp.tx('sfx'), 'Fixture Person no phone', pg_temp.link('gf') || chr(10) || 'WhatsApp Number ' || pg_temp.ph(65),
              pg_temp.sg(pg_temp.today() + 313, '15:00')),
  -- all day
  jsonb_build_object('id', 'cb480gg' || pg_temp.tx('sfx'), 'summary', 'Fixture holiday', 'start', jsonb_build_object('date', pg_temp.d(314)),
                     'end', jsonb_build_object('date', pg_temp.d(315)), 'updated', pg_temp.iso(now())),
  -- the webhook's: as it is (newer copy, same time), moved by a later edit (newer copy), an older copy (moved, but stale)
  pg_temp.gev('cb480gh' || pg_temp.tx('sfx'), 'Fixture Person ' || pg_temp.ph(140), pg_temp.link('wb1'), pg_temp.sg(pg_temp.today() + 313, '10:00')),
  pg_temp.gev('cb480gi' || pg_temp.tx('sfx'), 'Fixture Person ' || pg_temp.ph(141), pg_temp.link('wb2'), pg_temp.sg(pg_temp.today() + 314, '15:00')),
  pg_temp.gev('cb480gj' || pg_temp.tx('sfx'), 'Fixture Person ' || pg_temp.ph(142), pg_temp.link('wb3'), pg_temp.sg(pg_temp.today() + 315, '16:00'),
              'confirmed', now() - interval '3 days'),
  -- written without an offset, in its own zone (10 am in Sydney)
  jsonb_build_object('id', 'cb480gk' || pg_temp.tx('sfx'), 'summary', 'Fixture Person ' || pg_temp.ph(66), 'description', pg_temp.link('gk'),
                     'status', 'confirmed', 'updated', pg_temp.iso(now() - interval '1 hour'),
                     'start', jsonb_build_object('dateTime', pg_temp.d(316) || 'T10:00:00', 'timeZone', 'Australia/Sydney'),
                     'end', jsonb_build_object('dateTime', pg_temp.d(316) || 'T11:00:00', 'timeZone', 'Australia/Sydney')),
  -- no 'updated': taken as now, counted
  jsonb_build_object('id', 'cb480gl' || pg_temp.tx('sfx'), 'summary', 'Fixture Person ' || pg_temp.ph(67), 'description', pg_temp.link('gl'),
                     'status', 'confirmed', 'start', pg_temp.gt(pg_temp.sg(pg_temp.today() + 317, '10:00')),
                     'end', pg_temp.gt(pg_temp.sg(pg_temp.today() + 317, '11:00'))),
  -- shapes that cannot be read (skipped, counted; the call goes on): not an object; no id; a start that is no
  -- moment; a zone that is no zone; an 'updated' that is no moment; an end that is no moment
  '"text"'::jsonb,
  jsonb_build_object('summary', 'no id ' || pg_temp.ph(68), 'description', pg_temp.link('gm'), 'updated', pg_temp.iso(now()),
                     'start', pg_temp.gt(pg_temp.sg(pg_temp.today() + 318, '10:00')), 'end', pg_temp.gt(pg_temp.sg(pg_temp.today() + 318, '11:00'))),
  jsonb_build_object('id', 'cb480gn' || pg_temp.tx('sfx'), 'summary', 'Fixture Person ' || pg_temp.ph(69), 'description', pg_temp.link('gn'),
                     'updated', pg_temp.iso(now()), 'start', jsonb_build_object('dateTime', 'soon'), 'end', jsonb_build_object('dateTime', 'later')),
  jsonb_build_object('id', 'cb480go' || pg_temp.tx('sfx'), 'summary', 'Fixture Person ' || pg_temp.ph(69), 'description', pg_temp.link('go'),
                     'updated', pg_temp.iso(now()), 'start', jsonb_build_object('dateTime', pg_temp.d(318) || 'T10:00:00', 'timeZone', 'Mars/Base'),
                     'end', jsonb_build_object('dateTime', pg_temp.d(318) || 'T11:00:00', 'timeZone', 'Mars/Base')),
  jsonb_build_object('id', 'cb480gp' || pg_temp.tx('sfx'), 'summary', 'Fixture Person ' || pg_temp.ph(69), 'description', pg_temp.link('gp'),
                     'updated', 'yesterday', 'start', pg_temp.gt(pg_temp.sg(pg_temp.today() + 318, '10:00')),
                     'end', pg_temp.gt(pg_temp.sg(pg_temp.today() + 318, '11:00'))),
  jsonb_build_object('id', 'cb480gq' || pg_temp.tx('sfx'), 'summary', 'Fixture Person ' || pg_temp.ph(69), 'description', pg_temp.link('gq'),
                     'updated', pg_temp.iso(now()), 'start', pg_temp.gt(pg_temp.sg(pg_temp.today() + 318, '10:00')),
                     'end', jsonb_build_object('dateTime', pg_temp.d(318) || 'T25:00:00+08:00'))
)::text);
select pg_temp.put('rows0', (select count(*)::text from public.calcom_bookings));
select pg_temp.put('webrows0', pg_temp.rows_text(array['wb1', 'wb2', 'wb3', 'wm1', 'wo1', 'wl1']));
select pg_temp.put('dry', pg_temp.fill(pg_temp.tx('fill')::jsonb)::text);
select pg_temp.put('sydney', pg_temp.sgs(((pg_temp.today() + 316) + time '10:00') at time zone 'Australia/Sydney'));
select pg_temp.put('b1_ga2', 'repeated_uid ga ' || pg_temp.sgs(pg_temp.sg(pg_temp.today() + 311, '14:00')) || ' ' || pg_temp.sgs(pg_temp.sg(pg_temp.today() + 310, '14:00')));
select pg_temp.put('b1_wb3', 'kept_newer wb3 ' || pg_temp.sgs(pg_temp.sg(pg_temp.today() + 315, '16:00')) || ' ' || pg_temp.sgs(pg_temp.sg(pg_temp.today() + 315, '10:00')));
select pg_temp.put('b1_changes', concat_ws(' | ',
  'missing_from_calendar wm1 ' || pg_temp.sgs(pg_temp.sg(pg_temp.today() + 316, '10:00')) || ' -',
  'created ga - ' || pg_temp.sgs(pg_temp.sg(pg_temp.today() + 310, '14:00')),
  pg_temp.tx('b1_ga2'),
  'cancelled gc ' || pg_temp.sgs(pg_temp.sg(pg_temp.today() + 312, '14:00')) || ' -',
  'created gd - ' || pg_temp.sgs(pg_temp.sg(pg_temp.today() + 312, '11:00')),
  'moved wb2 ' || pg_temp.sgs(pg_temp.sg(pg_temp.today() + 314, '10:00')) || ' ' || pg_temp.sgs(pg_temp.sg(pg_temp.today() + 314, '15:00')),
  pg_temp.tx('b1_wb3'),
  'created gk - ' || pg_temp.tx('sydney'),
  'created gl - ' || pg_temp.sgs(pg_temp.sg(pg_temp.today() + 317, '10:00'))));
select pg_temp.check(pg_temp.counts(pg_temp.tx('dry')::jsonb) = '{"dry_run": true, "events": 18, "created": 4, "moved": 1, "unchanged": 1, "stale": 1,
                       "cancelled": 1, "terminal": 0, "repeated_uid": 1, "skipped_all_day": 1, "skipped_bad_shape": 6, "skipped_deleted_no_data": 0,
                       "skipped_no_link": 1, "skipped_no_phone": 1, "no_updated_time": 1, "missing_from_calendar": 1, "cancelled_missing": 0,
                       "cancel_uids_not_missing": 0, "truncated": false}'::jsonb
    and pg_temp.changes(pg_temp.tx('dry')::jsonb) = pg_temp.tx('b1_changes')
    and (select count(*)::text from public.calcom_bookings) = pg_temp.tx('rows0')
    and pg_temp.rows_text(array['wb1', 'wb2', 'wb3', 'wm1', 'wo1', 'wl1']) = pg_temp.tx('webrows0'),
  'B1 a dry run counts and lists, writing nothing: missing from the calendar first (the webhook''s booking it no longer carries, not the one outside the window nor the one stored after the listing began); created (a Cxl title, a reschedule link, a time in its own zone, one without updated: when the listing began), a copy listed twice (repeated, listed), one listed cancelled, the webhook''s as it is (unchanged), moved by a later edit (moved), an older copy at another time (stale, listed kept_newer); skipped all-day, no link, no number, six shapes that cannot be read: ' || pg_temp.tx('dry'));
select pg_temp.check((select (j ->> 'created')::int + (j ->> 'moved')::int + (j ->> 'unchanged')::int + (j ->> 'stale')::int + (j ->> 'cancelled')::int
                             + (j ->> 'terminal')::int + (j ->> 'repeated_uid')::int + (j ->> 'skipped_all_day')::int + (j ->> 'skipped_bad_shape')::int
                             + (j ->> 'skipped_deleted_no_data')::int + (j ->> 'skipped_no_link')::int + (j ->> 'skipped_no_phone')::int
                        from (select pg_temp.tx('dry')::jsonb as j) x) = 18,
  'B1b each event has exactly one outcome (the outcomes add up to the events listed)');
-- B2 the same listing for real: what the dry run said, and the rows.
select pg_temp.put('fill1', pg_temp.fill(pg_temp.tx('fill')::jsonb, false)::text);
select pg_temp.check(pg_temp.tx('fill1')::jsonb = pg_temp.tx('dry')::jsonb || '{"dry_run": false}'
    and (select (status, start_at, end_at, phone_key, email_key, source, last_trigger, date_trunc('milliseconds', last_event_at))
                is not distinct from ('active'::text, pg_temp.sg(pg_temp.today() + 310, '14:00'), pg_temp.sg(pg_temp.today() + 310, '15:00'),
                                      pg_temp.ph(60), null::text, 'backfill'::text, null::text, date_trunc('milliseconds', now() - interval '1 hour'))
           from pg_temp.row('ga'))
    and (select (status, phone_key, source) is not distinct from ('cancelled'::text, null::text, 'backfill'::text) from pg_temp.row('gc'))
    and (select (status, phone_key) is not distinct from ('active'::text, pg_temp.ph(63)) from pg_temp.row('gd'))
    and (select (status, start_at, source, last_trigger) is not distinct from
                ('active'::text, pg_temp.sg(pg_temp.today() + 313, '10:00'), 'webhook'::text, 'BOOKING_CREATED'::text) from pg_temp.row('wb1'))
    and (select (status, start_at, end_at, phone_key, source, last_trigger) is not distinct from
                ('active'::text, pg_temp.sg(pg_temp.today() + 314, '15:00'), pg_temp.sg(pg_temp.today() + 314, '16:00'), pg_temp.ph(141),
                 'backfill'::text, null::text) from pg_temp.row('wb2'))
    and (select (start_at, source) is not distinct from (pg_temp.sg(pg_temp.today() + 315, '10:00'), 'webhook'::text) from pg_temp.row('wb3'))
    and (select (status, start_at, phone_key) is not distinct from
                ('active'::text, ((pg_temp.today() + 316) + time '10:00') at time zone 'Australia/Sydney', pg_temp.ph(66)) from pg_temp.row('gk'))
    and (select last_event_at = now() from pg_temp.row('gl'))
    and (select status from pg_temp.row('wm1')) = 'active'
    and pg_temp.rows_text(array['wo1', 'wl1']) = (select string_agg(l, chr(10)) from unnest(string_to_array(pg_temp.tx('webrows0'), chr(10))) l
                                                   where l like '(' || pg_temp.uid('wo1') || ',%' or l like '(' || pg_temp.uid('wl1') || ',%')
    and not exists (select 1 from public.calcom_bookings where uid like 'gcal:%cb480%' or uid = pg_temp.uid('gb')),
  'B2 the same listing for real does what the dry run said: new bookings by phone (no email, timed by the Google event), the webhook''s moved by a newer edit (now the fill''s), an older copy left alone, the missing one only reported, the one outside the window and the one stored after the listing untouched: ' || pg_temp.tx('fill1'));
-- B3 the same listing again changes nothing (every row word for word).
select pg_temp.put('rows1', pg_temp.rows_text(array['ga', 'gc', 'gd', 'gk', 'gl', 'wb1', 'wb2', 'wb3', 'wm1', 'wo1', 'wl1']));
select pg_temp.put('fill2', pg_temp.fill(pg_temp.tx('fill')::jsonb, false)::text);
select pg_temp.check(pg_temp.counts(pg_temp.tx('fill2')::jsonb) = '{"dry_run": false, "events": 18, "created": 0, "moved": 0, "unchanged": 6, "stale": 1,
                       "cancelled": 0, "terminal": 1, "repeated_uid": 1, "skipped_all_day": 1, "skipped_bad_shape": 6, "skipped_deleted_no_data": 0,
                       "skipped_no_link": 1, "skipped_no_phone": 1, "no_updated_time": 1, "missing_from_calendar": 1, "cancelled_missing": 0,
                       "cancel_uids_not_missing": 0, "truncated": false}'::jsonb
    and pg_temp.changes(pg_temp.tx('fill2')::jsonb) = concat_ws(' | ', 'missing_from_calendar wm1 ' || pg_temp.sgs(pg_temp.sg(pg_temp.today() + 316, '10:00')) || ' -',
                                                                pg_temp.tx('b1_ga2'), pg_temp.tx('b1_wb3'))
    and pg_temp.rows_text(array['ga', 'gc', 'gd', 'gk', 'gl', 'wb1', 'wb2', 'wb3', 'wm1', 'wo1', 'wl1']) = pg_temp.tx('rows1'),
  'B3 the same listing again changes nothing (unchanged, the older copy still stale and listed, the cancelled one terminal; the missing one reported again): ' || pg_temp.tx('fill2'));
-- B4 missing from the calendar: cancelled only on a real run naming its uid in p_cancel_uids, and then no longer missing.
select pg_temp.put('b4dry', pg_temp.fill(pg_temp.tx('fill')::jsonb, true, array[pg_temp.uid('wm1')])::text);
select pg_temp.put('b4real', pg_temp.fill(pg_temp.tx('fill')::jsonb, false, array[pg_temp.uid('wm1')])::text);
select pg_temp.put('b4again', pg_temp.fill(pg_temp.tx('fill')::jsonb, false, array[pg_temp.uid('wm1')])::text);
select pg_temp.check((pg_temp.tx('b4dry')::jsonb ->> 'missing_from_calendar') = '1' and (pg_temp.tx('b4dry')::jsonb ->> 'cancelled_missing') = '1'
    and (pg_temp.tx('b4dry')::jsonb ->> 'cancel_uids_not_missing') = '0'
    and pg_temp.changes(pg_temp.tx('b4dry')::jsonb) = concat_ws(' | ', 'cancelled_missing wm1 ' || pg_temp.sgs(pg_temp.sg(pg_temp.today() + 316, '10:00')) || ' -',
                                                                pg_temp.tx('b1_ga2'), pg_temp.tx('b1_wb3'))
    and pg_temp.counts(pg_temp.tx('b4real')::jsonb) = pg_temp.counts(pg_temp.tx('b4dry')::jsonb) || '{"dry_run": false}'
    and pg_temp.changes(pg_temp.tx('b4real')::jsonb) = pg_temp.changes(pg_temp.tx('b4dry')::jsonb)
    and (select (status, phone_key, email_key, source, last_trigger) is not distinct from ('cancelled'::text, null::text, null::text, 'backfill'::text, null::text)
           from pg_temp.row('wm1'))
    and (pg_temp.tx('b4again')::jsonb ->> 'missing_from_calendar') = '0' and (pg_temp.tx('b4again')::jsonb ->> 'cancelled_missing') = '0'
    and (pg_temp.tx('b4again')::jsonb ->> 'cancel_uids_not_missing') = '1'
    and (select status from pg_temp.row('wo1')) = 'active' and (select status from pg_temp.row('wl1')) = 'active',
  'B4 a booking missing from the calendar: a dry run naming it in p_cancel_uids says it would cancel it (and does not); the real run cancels it (keeping no phone or email); then it is no longer missing, and naming it again cancels nothing (counted as not missing); outside the window and stored after the listing: untouched');
-- B5 a cancelled or rescheduled-away booking is never brought back, whatever the calendar shows.
select pg_temp.put('b5', pg_temp.fill(jsonb_build_array(
  pg_temp.gev('cb480wa' || pg_temp.tx('sfx'), 'Fixture Person ' || pg_temp.ph(143), pg_temp.link('wm1'), pg_temp.sg(pg_temp.today() + 316, '10:00'),
              'confirmed', now()),
  pg_temp.gev('cb480wc' || pg_temp.tx('sfx'), 'Fixture Person ' || pg_temp.ph(50), pg_temp.link('i1'), pg_temp.sg(pg_temp.today() + 5, '14:00'),
              'confirmed', now())), false)::text);
select pg_temp.check((pg_temp.tx('b5')::jsonb ->> 'terminal') = '2'
    and (select status from pg_temp.row('wm1')) = 'cancelled' and (select status from pg_temp.row('i1')) = 'rescheduled',
  'B5 a booking cancelled, or rescheduled away, listed again in the calendar (even by a newer event) stays so (terminal): ' || pg_temp.counts(pg_temp.tx('b5')::jsonb)::text);
-- B6 a webhook after a fill is ordered by its time: newer cancels or moves the fill's booking, older is stale.
select pg_temp.check(pg_temp.ingest(pg_temp.ev('BOOKING_CANCELLED', now(), jsonb_build_object('uid', pg_temp.uid('gd')))) = 'updated'
    and (select (status, source) is not distinct from ('cancelled'::text, 'webhook'::text) from pg_temp.row('gd'))
    and pg_temp.ingest(pg_temp.ev('BOOKING_CREATED', now() - interval '2 days',
          pg_temp.bk('ga', pg_temp.sg(pg_temp.today() + 309, '09:00'), pg_temp.ph(60), null))) = 'stale'
    and (select (start_at, source) is not distinct from (pg_temp.sg(pg_temp.today() + 310, '14:00'), 'backfill'::text) from pg_temp.row('ga'))
    and pg_temp.ingest(pg_temp.ev('BOOKING_RESCHEDULED', now() - interval '30 minutes',
          pg_temp.bk('gk', pg_temp.sg(pg_temp.today() + 318, '10:00'), pg_temp.ph(66), null, jsonb_build_object('rescheduleUid', pg_temp.uid('gk'))))) = 'updated'
    and (select (start_at, source, last_trigger) is not distinct from (pg_temp.sg(pg_temp.today() + 318, '10:00'), 'webhook'::text, 'BOOKING_RESCHEDULED'::text)
           from pg_temp.row('gk'))
    and (select count(*) from public.calcom_bookings where uid in (pg_temp.uid('ga'), pg_temp.uid('gd'), pg_temp.uid('gk'))) = 3,
  'B6 a webhook for a filled booking reaches the same row, ordered by its time: a newer cancellation cancels it, a newer reschedule moves it, an older creation is stale');
-- B7 cal.com writes its own manage link LAST (after the attendee's notes and answers, getRichDescription; only a
-- payment link, which is not read, can follow it): a booking or reschedule link typed into a note before it is not
-- the booking's uid, and a later webhook for the booking reaches the row.
select pg_temp.put('b7', pg_temp.fill(jsonb_build_array(
  pg_temp.gev('cb480lj' || pg_temp.tx('sfx'), 'Fixture Person ' || pg_temp.ph(70) || ' Fixture Centre',
              'What: Fixture' || chr(10) || 'Additional notes:' || chr(10) || 'moved from https://cal.com/booking/' || pg_temp.uid('lk')
              || '?changes=true and https://cal.com/reschedule/' || pg_temp.uid('ll') || chr(10)
              || 'Need to make a change? Cancel or reschedule: https://app.cal.com/booking/' || pg_temp.uid('lj') || '?changes=true' || chr(10)
              || 'Pay: https://app.cal.com/payment/' || pg_temp.uid('lm'),
              pg_temp.sg(pg_temp.today() + 320, '14:00'))), false)::text);
select pg_temp.check(pg_temp.tx('b7')::jsonb ->> 'created' = '1'
    and (select (status, phone_key, source) is not distinct from ('active'::text, pg_temp.ph(70), 'backfill'::text) from pg_temp.row('lj'))
    and not exists (select 1 from public.calcom_bookings where uid in (pg_temp.uid('lk'), pg_temp.uid('ll'), pg_temp.uid('lm')))
    and pg_temp.ingest(pg_temp.ev('BOOKING_CANCELLED', now(), jsonb_build_object('uid', pg_temp.uid('lj')))) = 'updated'
    and (select count(*) from public.calcom_bookings where uid in (pg_temp.uid('lj'), pg_temp.uid('lk'), pg_temp.uid('ll'), pg_temp.uid('lm'))) = 1
    and (select status from pg_temp.row('lj')) = 'cancelled',
  'B7 the uid is cal.com''s own manage link (the last booking or reschedule link), not one the attendee typed in a note before it, nor a payment link after it; its later cancellation reaches that row: ' || pg_temp.counts(pg_temp.tx('b7')::jsonb)::text);
-- B8 a booking listed twice: its live copy most recently updated, wherever it is listed; a deleted copy only when
-- no copy is live; a deleted event Google lists bare (its id and status alone) is counted as such, a deleted
-- all-day event as all-day.
select pg_temp.put('b8', pg_temp.fill(jsonb_build_array(
  pg_temp.gev('cb480ja' || pg_temp.tx('sfx'), 'Fixture Person ' || pg_temp.ph(71), pg_temp.link('ja'), pg_temp.sg(pg_temp.today() + 321, '10:00'),
              'confirmed', now() - interval '3 hours'),
  pg_temp.gev('cb480jb' || pg_temp.tx('sfx'), 'Fixture Person ' || pg_temp.ph(71), pg_temp.link('ja'), pg_temp.sg(pg_temp.today() + 321, '15:00'),
              'confirmed', now() - interval '2 hours'),
  pg_temp.gev('cb480jc' || pg_temp.tx('sfx'), 'Fixture Person ' || pg_temp.ph(72), pg_temp.link('jc'), pg_temp.sg(pg_temp.today() + 322, '10:00'),
              'cancelled', now() - interval '1 hour'),
  pg_temp.gev('cb480jd' || pg_temp.tx('sfx'), 'Fixture Person ' || pg_temp.ph(72), pg_temp.link('jc'), pg_temp.sg(pg_temp.today() + 322, '10:00'),
              'confirmed', now() - interval '2 hours'),
  jsonb_build_object('id', 'cb480je' || pg_temp.tx('sfx'), 'status', 'cancelled'),
  jsonb_build_object('id', 'cb480jf' || pg_temp.tx('sfx'), 'status', 'cancelled', 'summary', 'Fixture holiday',
                     'start', jsonb_build_object('date', pg_temp.d(323)))), false)::text);
select pg_temp.check(pg_temp.counts(pg_temp.tx('b8')::jsonb) - 'missing_from_calendar' = '{"dry_run": false, "events": 6, "created": 2, "moved": 0, "unchanged": 0,
                       "stale": 0, "cancelled": 0, "terminal": 0, "repeated_uid": 2, "skipped_all_day": 1, "skipped_bad_shape": 0,
                       "skipped_deleted_no_data": 1, "skipped_no_link": 0, "skipped_no_phone": 0, "no_updated_time": 0, "cancelled_missing": 0,
                       "cancel_uids_not_missing": 0, "truncated": false}'::jsonb
    and (select (status, start_at, phone_key) is not distinct from ('active'::text, pg_temp.sg(pg_temp.today() + 321, '10:00'), pg_temp.ph(71)) from pg_temp.row('ja'))
    and (select (status, start_at, phone_key) is not distinct from ('active'::text, pg_temp.sg(pg_temp.today() + 322, '10:00'), pg_temp.ph(72)) from pg_temp.row('jc'))
    and pg_temp.changes_nm(pg_temp.tx('b8')::jsonb) = concat_ws(' | ',
          'created ja - ' || pg_temp.sgs(pg_temp.sg(pg_temp.today() + 321, '10:00')),
          'repeated_uid ja ' || pg_temp.sgs(pg_temp.sg(pg_temp.today() + 321, '15:00')) || ' ' || pg_temp.sgs(pg_temp.sg(pg_temp.today() + 321, '10:00')),
          'repeated_uid jc ' || pg_temp.sgs(pg_temp.sg(pg_temp.today() + 322, '10:00')) || ' ' || pg_temp.sgs(pg_temp.sg(pg_temp.today() + 322, '10:00')),
          'created jc - ' || pg_temp.sgs(pg_temp.sg(pg_temp.today() + 322, '10:00'))),
  'B8 a booking listed twice: one not seen before takes its earliest copy (not the one updated last); a live copy beats a deleted one; each other copy is listed (repeated_uid: its start, then the start read); a bare deleted event is not all-day: ' || pg_temp.tx('b8'));
-- B8b a staff Duplicate of a cal.com event in Google copies its description, so the copy carries cal.com's link: a
-- stored booking stays where a listed copy still starts (ka: the webhook's, untouched, with a Duplicate a week later);
-- a booking not seen before takes its earliest copy (kd, its Duplicate listed first); with no copy at the stored start,
-- the copy updated last (kc: cal.com's event dragged to the next day in Google). Every other copy is listed. The same
-- listing again changes nothing.
select pg_temp.ingest(pg_temp.ev('BOOKING_CREATED', now() - interval '2 days', pg_temp.bk(x.tag, pg_temp.sg(pg_temp.today() + 330, '10:00'), pg_temp.ph(x.n), null)))
  from (values ('ka', 73), ('kc', 75)) x(tag, n);
select pg_temp.put('b8b_list', jsonb_build_array(
  pg_temp.gev('cb480ka' || pg_temp.tx('sfx'), 'Fixture Person ' || pg_temp.ph(73), pg_temp.link('ka'), pg_temp.sg(pg_temp.today() + 330, '10:00'),
              'confirmed', now() - interval '2 days 1 second'),
  pg_temp.gev('cb480kb' || pg_temp.tx('sfx'), 'Fixture Person ' || pg_temp.ph(73), pg_temp.link('ka'), pg_temp.sg(pg_temp.today() + 337, '10:00'),
              'confirmed', now() - interval '1 hour'),
  pg_temp.gev('cb480kf' || pg_temp.tx('sfx'), 'Fixture Person ' || pg_temp.ph(74), pg_temp.link('kd'), pg_temp.sg(pg_temp.today() + 338, '10:00'),
              'confirmed', now() - interval '1 hour'),
  pg_temp.gev('cb480ke' || pg_temp.tx('sfx'), 'Fixture Person ' || pg_temp.ph(74), pg_temp.link('kd'), pg_temp.sg(pg_temp.today() + 331, '10:00'),
              'confirmed', now() - interval '2 days'),
  pg_temp.gev('cb480kg' || pg_temp.tx('sfx'), 'Fixture Person ' || pg_temp.ph(75), pg_temp.link('kc'), pg_temp.sg(pg_temp.today() + 331, '10:00'),
              'confirmed', now() - interval '2 hours'),
  pg_temp.gev('cb480kh' || pg_temp.tx('sfx'), 'Fixture Person ' || pg_temp.ph(75), pg_temp.link('kc'), pg_temp.sg(pg_temp.today() + 337, '10:00'),
              'confirmed', now() - interval '3 hours'))::text);
select pg_temp.put('b8b', pg_temp.fill(pg_temp.tx('b8b_list')::jsonb, false)::text);
select pg_temp.put('b8b_again', pg_temp.fill(pg_temp.tx('b8b_list')::jsonb, false)::text);
select pg_temp.put('b8b_rep', concat_ws(' | ',
  'repeated_uid ka ' || pg_temp.sgs(pg_temp.sg(pg_temp.today() + 337, '10:00')) || ' ' || pg_temp.sgs(pg_temp.sg(pg_temp.today() + 330, '10:00')),
  'repeated_uid kd ' || pg_temp.sgs(pg_temp.sg(pg_temp.today() + 338, '10:00')) || ' ' || pg_temp.sgs(pg_temp.sg(pg_temp.today() + 331, '10:00'))));
select pg_temp.check(pg_temp.counts(pg_temp.tx('b8b')::jsonb) - 'missing_from_calendar' = '{"dry_run": false, "events": 6, "created": 1, "moved": 1, "unchanged": 1,
                       "stale": 0, "cancelled": 0, "terminal": 0, "repeated_uid": 3, "skipped_all_day": 0, "skipped_bad_shape": 0,
                       "skipped_deleted_no_data": 0, "skipped_no_link": 0, "skipped_no_phone": 0, "no_updated_time": 0, "cancelled_missing": 0,
                       "cancel_uids_not_missing": 0, "truncated": false}'::jsonb
    and pg_temp.changes_nm(pg_temp.tx('b8b')::jsonb) = concat_ws(' | ', pg_temp.tx('b8b_rep'),
          'created kd - ' || pg_temp.sgs(pg_temp.sg(pg_temp.today() + 331, '10:00')),
          'moved kc ' || pg_temp.sgs(pg_temp.sg(pg_temp.today() + 330, '10:00')) || ' ' || pg_temp.sgs(pg_temp.sg(pg_temp.today() + 331, '10:00')),
          'repeated_uid kc ' || pg_temp.sgs(pg_temp.sg(pg_temp.today() + 337, '10:00')) || ' ' || pg_temp.sgs(pg_temp.sg(pg_temp.today() + 331, '10:00')))
    and (select (status, start_at, source) is not distinct from ('active'::text, pg_temp.sg(pg_temp.today() + 330, '10:00'), 'webhook'::text) from pg_temp.row('ka'))
    and (select (status, start_at, source) is not distinct from ('active'::text, pg_temp.sg(pg_temp.today() + 331, '10:00'), 'backfill'::text) from pg_temp.row('kd'))
    and (select (status, start_at, source) is not distinct from ('active'::text, pg_temp.sg(pg_temp.today() + 331, '10:00'), 'backfill'::text) from pg_temp.row('kc'))
    and (pg_temp.tx('b8b_again')::jsonb ->> 'unchanged') = '3' and (pg_temp.tx('b8b_again')::jsonb ->> 'moved') = '0'
    and (pg_temp.tx('b8b_again')::jsonb ->> 'created') = '0'
    and pg_temp.changes_nm(pg_temp.tx('b8b_again')::jsonb) = concat_ws(' | ', pg_temp.tx('b8b_rep'),
          'repeated_uid kc ' || pg_temp.sgs(pg_temp.sg(pg_temp.today() + 337, '10:00')) || ' ' || pg_temp.sgs(pg_temp.sg(pg_temp.today() + 331, '10:00'))),
  'B8b a staff Duplicate (the same cal.com link) moves nothing while a copy still starts at the booking''s time; a new booking takes its earliest copy; with no copy at its time, the copy updated last; the other copies listed; again: nothing changes: '
  || pg_temp.counts(pg_temp.tx('b8b')::jsonb)::text || ' / ' || pg_temp.changes_nm(pg_temp.tx('b8b')::jsonb));
-- B9 a call that cannot be a listing of one window is refused (22023), naming what is wrong and never a value.
select pg_temp.put('b9', concat_ws(' | ',
  pg_temp.err('select public.calcom_booking_backfill(''{"id":"x"}''::jsonb, now(), now() + interval ''1 day'', now())'),
  pg_temp.err('select public.calcom_booking_backfill((select jsonb_agg(jsonb_build_object(''id'', ''e'' || g)) from generate_series(1, 5001) g), now(), now() + interval ''1 day'', now())'),
  pg_temp.err('select public.calcom_booking_backfill(''[]''::jsonb, null, now(), now())'),
  pg_temp.err('select public.calcom_booking_backfill(''[]''::jsonb, now(), null, now())'),
  pg_temp.err('select public.calcom_booking_backfill(''[]''::jsonb, now(), now() - interval ''1 day'', now())'),
  pg_temp.err('select public.calcom_booking_backfill(''[]''::jsonb, now(), now() + interval ''401 days'', now())'),
  pg_temp.err('select public.calcom_booking_backfill(''[]''::jsonb, now(), now() + interval ''1 day'', null)'),
  pg_temp.err('select public.calcom_booking_backfill(''[]''::jsonb, now(), now() + interval ''1 day'', now() + interval ''1 day'')'),
  pg_temp.err('select public.calcom_booking_backfill(''[]''::jsonb, now(), now() + interval ''1 day'', now(), false, array[''x''])'),
  pg_temp.err('select public.calcom_booking_backfill(''[]''::jsonb, now(), now() + interval ''400 days'', now())::text')));
select pg_temp.check(pg_temp.tx('b9') = concat_ws(' | ',
      '22023 calcom_booking_backfill: the events are not a JSON array',
      '22023 calcom_booking_backfill: at most 5000 events in one call',
      '22023 calcom_booking_backfill: p_from and p_to (the window listed) are needed',
      '22023 calcom_booking_backfill: p_from and p_to (the window listed) are needed',
      '22023 calcom_booking_backfill: the window must end after it starts and last at most 400 days',
      '22023 calcom_booking_backfill: the window must end after it starts and last at most 400 days',
      '22023 calcom_booking_backfill: p_listed_at (when the listing began) is needed and cannot be later than now',
      '22023 calcom_booking_backfill: p_listed_at (when the listing began) is needed and cannot be later than now',
      '22023 calcom_booking_backfill: p_cancel_uids with no event listed',
      'ok'),
  'B9 refused: not an array, more than 5000 events, no window, a window that ends first or lasts over 400 days, no p_listed_at or one in the future, p_cancel_uids with nothing listed (a 400-day window is accepted): ' || pg_temp.tx('b9'));
-- B9b a call written in round 2's form (a flag that cancelled every missing booking) no longer exists: it fails, cancelling nothing.
select pg_temp.check(pg_temp.err('select public.calcom_booking_backfill(''[]''::jsonb, now(), now() + interval ''1 day'', now(), false, true)') like '42883 %'
    and pg_temp.err('select public.calcom_booking_backfill(''[{"id":"x"}]''::jsonb, now(), now() + interval ''1 day'', now(), p_dry_run => false, p_cancel_missing => true)') like '42883 %'
    and pg_temp.err('select public.calcom_booking_backfill(''[{"id":"x"}]''::jsonb, now(), now() + interval ''1 day'', now(), p_dry_run => false, p_cancel_uids => true)') like '42883 %',
  'B9b a call with round 2''s cancel-every-missing flag (by position or by name), or with a flag where the uids go, does not exist (42883)');
-- B10 the answer holds counts, uids and times: no phone, email, name, title or description.
select pg_temp.check(pg_temp.tx('dry') !~ '\+6125550' and pg_temp.tx('dry') !~ '@' and pg_temp.tx('dry') !~* 'fixture|cxl|whatsapp|hand typed|holiday|what:'
    and (select bool_and((select array_agg(k order by k) from jsonb_object_keys(c) k) = array['change', 'new_start', 'old_start', 'uid']
                         and c ->> 'uid' ~ '^(gcal:)?[A-Za-z0-9_-]+$'
                         and coalesce(c ->> 'old_start', '2000-01-01T00:00:00+08:00') ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+08:00$'
                         and coalesce(c ->> 'new_start', '2000-01-01T00:00:00+08:00') ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\+08:00$')
           from jsonb_array_elements(pg_temp.tx('dry')::jsonb -> 'changes') c),
  'B10 the answer holds counts and, per change, the uid, the change and the old and new start in Singapore time: no phone, email, name, title or description');
-- B11 at most 500 changes are listed, then truncated (a dry run of 501 new bookings, nothing written).
select pg_temp.put('rows11', (select count(*)::text from public.calcom_bookings));
select pg_temp.put('b11', pg_temp.fill((select jsonb_agg(pg_temp.gev('cb480t' || g || pg_temp.tx('sfx'), 'Fixture Person ' || pg_temp.ph(146),
                                                              pg_temp.link('t' || g), pg_temp.sg(pg_temp.today() + 330, '10:00')))
                                          from generate_series(1, 501) g))::text);
select pg_temp.check(pg_temp.tx('b11')::jsonb ->> 'created' = '501' and jsonb_array_length(pg_temp.tx('b11')::jsonb -> 'changes') = 500
    and pg_temp.tx('b11')::jsonb ->> 'truncated' = 'true' and (select count(*)::text from public.calcom_bookings) = pg_temp.tx('rows11'),
  'B11 a dry run of 501 new bookings lists 500 changes and says truncated; nothing written');
-- B11b the bookings missing from the calendar are listed first, so the Owner sees every one even when the other changes
-- are cut at 500: a webhook booking in the window that the 501-event listing does not carry, named for cancelling, is
-- listed as cancelled_missing in the dry run and in the real run (run in a savepoint, read, then undone).
select pg_temp.ingest(pg_temp.ev('BOOKING_CREATED', now() - interval '2 days', pg_temp.bk('vm1', pg_temp.sg(pg_temp.today() + 331, '10:00'), pg_temp.ph(148), null)));
select pg_temp.put('b11ev', (select jsonb_agg(pg_temp.gev('cb480t' || g || pg_temp.tx('sfx'), 'Fixture Person ' || pg_temp.ph(146),
                                                         pg_temp.link('t' || g), pg_temp.sg(pg_temp.today() + 330, '10:00')))
                               from generate_series(1, 501) g)::text);
select pg_temp.put('b11b', pg_temp.fill(pg_temp.tx('b11ev')::jsonb, true, array[pg_temp.uid('vm1')])::text);
savepoint b11b;
select pg_temp.fill(pg_temp.tx('b11ev')::jsonb, false, array[pg_temp.uid('vm1')])::text as b11b_real \gset
select (select status from pg_temp.row('vm1')) as b11b_vm1 \gset
rollback to savepoint b11b;
select pg_temp.check((pg_temp.tx('b11b')::jsonb ->> 'truncated') = 'true' and (pg_temp.tx('b11b')::jsonb ->> 'created') = '501'
    and (pg_temp.tx('b11b')::jsonb ->> 'cancelled_missing') = '1' and (pg_temp.tx('b11b')::jsonb ->> 'missing_from_calendar')::int > 1
    and (select count(*) from jsonb_array_elements(pg_temp.tx('b11b')::jsonb -> 'changes') with ordinality x(c, n)
          where c ->> 'change' in ('missing_from_calendar', 'cancelled_missing') and n <= (pg_temp.tx('b11b')::jsonb ->> 'missing_from_calendar')::int)
        = (pg_temp.tx('b11b')::jsonb ->> 'missing_from_calendar')::int
    and exists (select 1 from jsonb_array_elements(pg_temp.tx('b11b')::jsonb -> 'changes') c
                 where c ->> 'uid' = pg_temp.uid('vm1') and c ->> 'change' = 'cancelled_missing')
    and pg_temp.changes(:'b11b_real'::jsonb) = pg_temp.changes(pg_temp.tx('b11b')::jsonb)
    and :'b11b_vm1' = 'cancelled' and (select status from pg_temp.row('vm1')) = 'active',
  'B11b with 501 creations cut at 500, every booking missing from the calendar is listed first, in the dry run naming one for cancelling and in the real run that cancels it: ' || pg_temp.counts(pg_temp.tx('b11b')::jsonb)::text);
-- B12 asked to, events without a cal.com link are kept as gcal:<event id>, the number read from a word of the title
-- (not run into " - 3in1"), or typed with spaces; listed again without the flag they are not missing.
select pg_temp.put('b12ev', jsonb_build_array(
  pg_temp.gev('cb480ge' || pg_temp.tx('sfx'), '(Fixture) Hand Typed ' || pg_temp.ph(64) || ' - 3in1', 'typed by staff', pg_temp.sg(pg_temp.today() + 313, '14:00')),
  pg_temp.gev('cb480gs' || pg_temp.tx('sfx'), 'Fixture Spaced ' || regexp_replace(pg_temp.ph(147), '^\+61(\d)(\d{4})(\d{4})$', '+61 \1 \2 \3') || ' Voucher',
              null, pg_temp.sg(pg_temp.today() + 313, '15:00')))::text);
select pg_temp.put('b12', pg_temp.fill(pg_temp.tx('b12ev')::jsonb, false, null, true)::text);
select pg_temp.put('b12b', pg_temp.fill(pg_temp.tx('b12ev')::jsonb)::text);
select pg_temp.check(pg_temp.tx('b12')::jsonb ->> 'created' = '2'
    and (select (status, phone_key, source) is not distinct from ('active'::text, pg_temp.ph(64), 'backfill'::text)
           from public.calcom_bookings where uid = 'gcal:cb480ge' || pg_temp.tx('sfx'))
    and (select phone_key from public.calcom_bookings where uid = 'gcal:cb480gs' || pg_temp.tx('sfx')) = pg_temp.ph(147)
    and pg_temp.tx('b12b')::jsonb ->> 'skipped_no_link' = '2' and pg_temp.tx('b12b') !~ 'gcal:',
  'B12 asked to, events without a cal.com link are kept as gcal:<event id> (the number read from a word of the title, not run into " - 3in1", or typed with spaces); listed again without asking, they are skipped and not missing: ' || pg_temp.tx('b12'));
-- B13 a stored booking's event with no number in its title still moves it; its phone stays.
select pg_temp.put('b13', pg_temp.fill(jsonb_build_array(
  pg_temp.gev('cb480ga' || pg_temp.tx('sfx'), 'Cxl no number here', pg_temp.link('ga'), pg_temp.sg(pg_temp.today() + 310, '16:00'),
              'confirmed', now() - interval '30 minutes')), false)::text);
select pg_temp.check(pg_temp.tx('b13')::jsonb ->> 'moved' = '1'
    and (select (start_at, phone_key) is not distinct from (pg_temp.sg(pg_temp.today() + 310, '16:00'), pg_temp.ph(60)) from pg_temp.row('ga')),
  'B13 a stored booking whose calendar title lost its number is still moved, keeping its phone');
-- B14 a real run cancels only the uids p_cancel_uids names (the Owner's, from the dry run): its listing lost a page (wx1
-- and wx2), so they are reported missing and cancelled not; the named one is (wx3); a named uid the listing carries is
-- not missing: left alone, and counted.
select pg_temp.ingest(pg_temp.ev('BOOKING_CREATED', now() - interval '2 days', pg_temp.bk(x.tag, pg_temp.sg(pg_temp.today() + x.d, '10:00'), pg_temp.ph(x.n), null)))
  from (values ('wx1', 318, 149), ('wx2', 319, 150), ('wx3', 319, 151)) x(tag, d, n);
select pg_temp.put('b14ev', (pg_temp.tx('fill')::jsonb || jsonb_build_array(
  pg_temp.gev('cb480xa' || pg_temp.tx('sfx'), 'Fixture Person ' || pg_temp.ph(149), pg_temp.link('wx1'), pg_temp.sg(pg_temp.today() + 318, '10:00'),
              'confirmed', now() - interval '2 days'),
  pg_temp.gev('cb480xb' || pg_temp.tx('sfx'), 'Fixture Person ' || pg_temp.ph(150), pg_temp.link('wx2'), pg_temp.sg(pg_temp.today() + 319, '10:00'),
              'confirmed', now() - interval '2 days')))::text);
select pg_temp.put('b14dry', pg_temp.fill(pg_temp.tx('b14ev')::jsonb, true, array[pg_temp.uid('wx3')])::text);
select pg_temp.put('b14real', pg_temp.fill(pg_temp.tx('fill')::jsonb, false, array[pg_temp.uid('wx3')])::text);
select pg_temp.put('b14named', pg_temp.fill(pg_temp.tx('b14ev')::jsonb, false, array[pg_temp.uid('wx1'), pg_temp.uid('wx1'), null])::text);
select pg_temp.check(pg_temp.changes(pg_temp.tx('b14dry')::jsonb) ~ 'cancelled_missing wx3 ' and pg_temp.changes(pg_temp.tx('b14dry')::jsonb) !~ 'wx1|wx2'
    and pg_temp.tx('b14dry')::jsonb ->> 'cancelled_missing' = '1' and pg_temp.tx('b14dry')::jsonb ->> 'cancel_uids_not_missing' = '0'
    and pg_temp.tx('b14real')::jsonb ->> 'cancelled_missing' = '1' and pg_temp.tx('b14real')::jsonb ->> 'cancel_uids_not_missing' = '0'
    and pg_temp.changes(pg_temp.tx('b14real')::jsonb) ~ 'missing_from_calendar wx1 ' and pg_temp.changes(pg_temp.tx('b14real')::jsonb) ~ 'missing_from_calendar wx2 '
    and pg_temp.changes(pg_temp.tx('b14real')::jsonb) ~ 'cancelled_missing wx3 '
    and (select (status, phone_key) is not distinct from ('active'::text, pg_temp.ph(149)) from pg_temp.row('wx1'))
    and (select (status, phone_key) is not distinct from ('active'::text, pg_temp.ph(150)) from pg_temp.row('wx2'))
    and (select (status, phone_key, source) is not distinct from ('cancelled'::text, null::text, 'backfill'::text) from pg_temp.row('wx3'))
    and pg_temp.tx('b14named')::jsonb ->> 'cancelled_missing' = '0' and pg_temp.tx('b14named')::jsonb ->> 'cancel_uids_not_missing' = '1'
    and (select (status, phone_key) is not distinct from ('active'::text, pg_temp.ph(149)) from pg_temp.row('wx1')),
  'B14 a real run whose listing lost a page cancels only the uid named from the dry run (wx3): wx1 and wx2, missing only from that listing, are reported and stay active with their phones; a named uid the listing carries is left alone and counted (cancel_uids_not_missing): ' || pg_temp.counts(pg_temp.tx('b14real')::jsonb)::text);
-- B15 an event cannot have changed after it was listed: an 'updated' later than now (10 minutes' leeway, as p_listed_at
-- has) is a shape that cannot be read: nothing stored or moved, and a later cal.com cancellation still cancels the booking.
select pg_temp.ingest(pg_temp.ev('BOOKING_CREATED', now() - interval '1 hour',
         pg_temp.bk('fu1', pg_temp.sg(pg_temp.today() + 374, '10:00'), pg_temp.ph(152), null)));
select pg_temp.put('b15', pg_temp.fill(jsonb_build_array(
  pg_temp.gev('cb480fu' || pg_temp.tx('sfx'), 'Fixture Person ' || pg_temp.ph(152), pg_temp.link('fu1'), pg_temp.sg(pg_temp.today() + 375, '10:00'),
              'confirmed', '2099-06-01 00:00:00+00'::timestamptz),
  pg_temp.gev('cb480fv' || pg_temp.tx('sfx'), 'Fixture Person ' || pg_temp.ph(153), pg_temp.link('fu2'), pg_temp.sg(pg_temp.today() + 376, '10:00'),
              'confirmed', now() + interval '11 minutes'),
  pg_temp.gev('cb480fw' || pg_temp.tx('sfx'), 'Fixture Person ' || pg_temp.ph(154), pg_temp.link('fu3'), pg_temp.sg(pg_temp.today() + 377, '10:00'),
              'confirmed', now() + interval '5 minutes')), false)::text);
select pg_temp.check(pg_temp.tx('b15')::jsonb ->> 'skipped_bad_shape' = '2' and pg_temp.tx('b15')::jsonb ->> 'created' = '1'
    and pg_temp.tx('b15')::jsonb ->> 'stale' = '0' and pg_temp.tx('b15')::jsonb ->> 'moved' = '0'
    and pg_temp.changes_nm(pg_temp.tx('b15')::jsonb) = 'created fu3 - ' || pg_temp.sgs(pg_temp.sg(pg_temp.today() + 377, '10:00'))
    and (select (status, start_at, source, last_trigger) is not distinct from
                ('active'::text, pg_temp.sg(pg_temp.today() + 374, '10:00'), 'webhook'::text, 'BOOKING_CREATED'::text) from pg_temp.row('fu1'))
    and not exists (select 1 from public.calcom_bookings where uid = pg_temp.uid('fu2'))
    and (select (status, last_event_at) is not distinct from ('active'::text, date_trunc('milliseconds', now() + interval '5 minutes')) from pg_temp.row('fu3'))
    and pg_temp.ingest(pg_temp.ev('BOOKING_CANCELLED', now(), jsonb_build_object('uid', pg_temp.uid('fu1')))) = 'updated'
    and (select status from pg_temp.row('fu1')) = 'cancelled',
  'B15 a Google ''updated'' later than now (2099; 11 minutes ahead) is a shape that cannot be read: nothing stored or moved (5 minutes ahead is clock leeway: read); a later cal.com cancellation still applies: '
  || pg_temp.counts(pg_temp.tx('b15')::jsonb)::text);
-- B16 an event listed without 'updated' is timed when the listing began (p_listed_at), not when the call runs: a webhook
-- that moved the booking (the same uid) after the listing, before the Owner's OK, is not undone by the real run; the dry
-- run after that webhook lists the calendar's older time as kept_newer instead of offering to undo it.
select pg_temp.ingest(pg_temp.ev('BOOKING_CREATED', now() - interval '5 hours', pg_temp.bk('nu1', pg_temp.sg(pg_temp.today() + 324, '10:00'), pg_temp.ph(155), null)));
select pg_temp.put('b16ev', jsonb_build_array(jsonb_build_object('id', 'cb480nu' || pg_temp.tx('sfx'), 'summary', 'Fixture Person ' || pg_temp.ph(155),
  'description', pg_temp.link('nu1'), 'status', 'confirmed', 'start', pg_temp.gt(pg_temp.sg(pg_temp.today() + 324, '10:00')),
  'end', pg_temp.gt(pg_temp.sg(pg_temp.today() + 324, '11:00'))))::text);
select pg_temp.put('b16dry', pg_temp.fill(pg_temp.tx('b16ev')::jsonb, true, null, false, now() - interval '3 hours')::text);
select pg_temp.ingest(pg_temp.ev('BOOKING_RESCHEDULED', now() - interval '1 hour', pg_temp.bk('nu1', pg_temp.sg(pg_temp.today() + 331, '16:00'), pg_temp.ph(155), null)));
select pg_temp.put('b16dry2', pg_temp.fill(pg_temp.tx('b16ev')::jsonb, true, null, false, now() - interval '3 hours')::text);
select pg_temp.put('b16real', pg_temp.fill(pg_temp.tx('b16ev')::jsonb, false, null, false, now() - interval '3 hours')::text);
select pg_temp.put('b16kept', 'kept_newer nu1 ' || pg_temp.sgs(pg_temp.sg(pg_temp.today() + 324, '10:00')) || ' ' || pg_temp.sgs(pg_temp.sg(pg_temp.today() + 331, '16:00')));
select pg_temp.check(pg_temp.tx('b16dry')::jsonb ->> 'unchanged' = '1' and pg_temp.tx('b16dry')::jsonb ->> 'no_updated_time' = '1'
    and pg_temp.changes(pg_temp.tx('b16dry')::jsonb) = ''
    and pg_temp.tx('b16dry2')::jsonb ->> 'stale' = '1' and pg_temp.tx('b16dry2')::jsonb ->> 'moved' = '0'
    and pg_temp.tx('b16real')::jsonb ->> 'stale' = '1' and pg_temp.tx('b16real')::jsonb ->> 'moved' = '0'
    and pg_temp.tx('b16real')::jsonb ->> 'no_updated_time' = '1'
    and pg_temp.changes(pg_temp.tx('b16dry2')::jsonb) = pg_temp.tx('b16kept') and pg_temp.changes(pg_temp.tx('b16real')::jsonb) = pg_temp.tx('b16kept')
    and (select (start_at, source, last_trigger) is not distinct from (pg_temp.sg(pg_temp.today() + 331, '16:00'), 'webhook'::text, 'BOOKING_RESCHEDULED'::text)
           from pg_temp.row('nu1')),
  'B16 an event without updated is timed when the listing began: a webhook move after the listing is not undone by the real run (the first dry run showed it unchanged), and is listed as kept_newer: '
  || pg_temp.tx('b16dry') || ' | ' || pg_temp.tx('b16real'));
-- B17 the ordinary case: cal.com writes its Google event a moment BEFORE it sends the webhook, so an untouched booking's
-- copy is older than the stored booking: unchanged when it agrees (not stale); an older copy at another time is stale
-- and listed (kept_newer: the calendar's start, then the start kept); nothing written. Its own window (371 to 373).
select pg_temp.ingest(pg_temp.ev('BOOKING_CREATED', now() - interval '2 days', pg_temp.bk(x.tag, pg_temp.sg(pg_temp.today() + x.d, '10:00'), pg_temp.ph(x.n), null)))
  from (values ('wq1', 371, 156), ('wq2', 372, 157)) x(tag, d, n);
select pg_temp.put('b17_rows0', pg_temp.rows_text(array['wq1', 'wq2']));
select pg_temp.put('b17', public.calcom_booking_backfill(jsonb_build_array(
    pg_temp.gev('cb480qa' || pg_temp.tx('sfx'), 'Fixture Person ' || pg_temp.ph(156), pg_temp.link('wq1'), pg_temp.sg(pg_temp.today() + 371, '10:00'),
                'confirmed', now() - interval '2 days 2 seconds'),
    pg_temp.gev('cb480qb' || pg_temp.tx('sfx'), 'Fixture Person ' || pg_temp.ph(157), pg_temp.link('wq2'), pg_temp.sg(pg_temp.today() + 372, '15:00'),
                'confirmed', now() - interval '2 days 2 seconds')),
  pg_temp.sg(pg_temp.today() + 371, '00:00'), pg_temp.sg(pg_temp.today() + 373, '00:00'), now(), false)::text);
select pg_temp.check(pg_temp.counts(pg_temp.tx('b17')::jsonb) = '{"dry_run": false, "events": 2, "created": 0, "moved": 0, "unchanged": 1, "stale": 1,
                       "cancelled": 0, "terminal": 0, "repeated_uid": 0, "skipped_all_day": 0, "skipped_bad_shape": 0, "skipped_deleted_no_data": 0,
                       "skipped_no_link": 0, "skipped_no_phone": 0, "no_updated_time": 0, "missing_from_calendar": 0, "cancelled_missing": 0,
                       "cancel_uids_not_missing": 0, "truncated": false}'::jsonb
    and pg_temp.changes(pg_temp.tx('b17')::jsonb) = 'kept_newer wq2 ' || pg_temp.sgs(pg_temp.sg(pg_temp.today() + 372, '15:00'))
                                                      || ' ' || pg_temp.sgs(pg_temp.sg(pg_temp.today() + 372, '10:00'))
    and pg_temp.rows_text(array['wq1', 'wq2']) = pg_temp.tx('b17_rows0'),
  'B17 an untouched booking''s calendar copy, written 2 s before the webhook, is unchanged (not stale); an older copy at another time is stale and listed as kept_newer; nothing written: ' || pg_temp.tx('b17'));

-- I13 a number the centre keeps as its own (ads_excluded_phones: its booking line, its landline; the calendar fill
-- leaves it out, as ads_extract_phones does) is no one's: the next phone is read, else the email.
do $$ declare v uuid; begin
  insert into public.ads_excluded_phones (phone_e164, label) values (substr(pg_temp.ph(80), 2), 'T480 fixture centre line');
  insert into public.customers (full_name, phone) values ('T480 Centre Line Holder', pg_temp.ph(80)) returning id into v;
  perform pg_temp.putx('h1', v);
  insert into public.customers (full_name, phone, email) values ('T480 Booked By Staff', pg_temp.ph(81), pg_temp.mail('bs')) returning id into v;
  perform pg_temp.putx('h2', v);
end $$;
select pg_temp.check(pg_temp.ingest(pg_temp.ev('BOOKING_CREATED', now(), pg_temp.bk('i13a', pg_temp.sg(pg_temp.today() + 4, '10:00'), pg_temp.ph(80), pg_temp.mail('bs'),
          jsonb_build_object('attendees', jsonb_build_array(jsonb_build_object('email', pg_temp.mail('bs'), 'phoneNumber', pg_temp.ph(81))))))) = 'created'
    and (select (phone_key, email_key) is not distinct from (pg_temp.ph(81), pg_temp.mail('bs')) from pg_temp.row('i13a'))
    and pg_temp.ingest(pg_temp.ev('BOOKING_CREATED', now(), jsonb_build_object('uid', pg_temp.uid('i13b'), 'startTime', pg_temp.iso(pg_temp.sg(pg_temp.today() + 5, '10:00')),
          'responses', jsonb_build_object('WhatsApp-Number', '+61 2 5550 ' || substr(pg_temp.ph(80), 9), 'smsReminderNumber', pg_temp.ph(80), 'email', pg_temp.mail('bs')),
          'attendees', jsonb_build_array(jsonb_build_object('phoneNumber', pg_temp.ph(80))), 'smsReminderNumber', pg_temp.ph(80)))) = 'created'
    and (select (phone_key, email_key) is not distinct from (null::text, pg_temp.mail('bs')) from pg_temp.row('i13b'))
    and pg_temp.st('h1') = 'none'
    and pg_temp.st('h2') = 'upcoming ' || pg_temp.iso(pg_temp.sg(pg_temp.today() + 4, '10:00'))
    and pg_temp.fill(jsonb_build_array(pg_temp.gev('cb480hi' || pg_temp.tx('sfx'), 'Fixture Person ' || pg_temp.ph(80) || ' Fixture Centre',
          pg_temp.link('i13c'), pg_temp.sg(pg_temp.today() + 4, '10:00')))) ->> 'skipped_no_phone' = '1',
  'I13 a number the centre keeps as its own (ads_excluded_phones) is no one''s, as in the calendar fill: the attendee''s phone is read instead, else the email; whoever holds that number shows none');
-- I14 an answer whose value is not text (a number, an object, a list) is not read: the next source is.
select pg_temp.check(pg_temp.ingest(pg_temp.ev('BOOKING_CREATED', now(), jsonb_build_object('uid', pg_temp.uid('i14a'), 'startTime', pg_temp.iso(pg_temp.sg(pg_temp.today() + 3, '10:00')),
          'responses', jsonb_build_object('WhatsApp-Number', jsonb_build_object('value', substr(pg_temp.ph(86), 2)::bigint),
                                          'email', jsonb_build_object('value', jsonb_build_object('a', 1))),
          'attendees', jsonb_build_array(jsonb_build_object('phoneNumber', pg_temp.ph(85), 'email', pg_temp.mail('i14a')))))) = 'created'
    and (select (phone_key, email_key) is not distinct from (pg_temp.ph(85), pg_temp.mail('i14a')) from pg_temp.row('i14a'))
    and pg_temp.ingest(pg_temp.ev('BOOKING_CREATED', now(), jsonb_build_object('uid', pg_temp.uid('i14b'), 'startTime', pg_temp.iso(pg_temp.sg(pg_temp.today() + 3, '10:00')),
          'responses', jsonb_build_object('smsReminderNumber', jsonb_build_object('value', jsonb_build_array(pg_temp.ph(87)))),
          'smsReminderNumber', pg_temp.ph(86)))) = 'created'
    and (select (phone_key, email_key) is not distinct from (pg_temp.ph(86), null::text) from pg_temp.row('i14b')),
  'I14 an answer whose value is not text is not read: a number or an object goes to the attendee''s phone and email, a list to the next phone');

-- ═════ M Matching (read whenever shown) ═════
select pg_temp.ingest(pg_temp.ev('BOOKING_CREATED', now(), pg_temp.bk(x.tag, pg_temp.sg(pg_temp.today() + x.d, '10:00'), x.phone, x.email)))
  from (values ('m1a', 2, pg_temp.ph(30), 't480shared.one' || pg_temp.tx('sfx') || '+cal@googlemail.com'),  -- s1 by Gmail spelling
               ('m2a', 3, pg_temp.ph(30), upper(pg_temp.mail('s2'))),                                         -- s2 by email
               ('m3a', 4, pg_temp.ph(30), pg_temp.mail('nobody')),                                            -- shared phone, deciding nothing
               ('m4a', 2, pg_temp.ph(99), pg_temp.mail('e1')),                                                -- a phone nobody has: by email
               ('m5a', 2, null, pg_temp.mail('qq')),                                                          -- an email two have: no one
               ('m6a', 2, pg_temp.ph(34), null),                                                              -- a deleted one and a living one
               ('m7a', 2, pg_temp.ph(35), null),                                                              -- only a deleted one
               ('m8a', 2, pg_temp.ph(36), null),                                                              -- twins: no one until merged
               ('m9a', 2, pg_temp.ph(37), null)) x(tag, d, phone, email);                                     -- before the customer exists
select pg_temp.check(public.calcom_booking_owner(pg_temp.ph(30), public.customer_email_match_key('T480Shared.One' || pg_temp.tx('sfx') || '+x@gmail.com')) = pg_temp.fx('s1')
    and public.calcom_booking_owner(pg_temp.ph(30), pg_temp.mail('s2')) = pg_temp.fx('s2')
    and public.calcom_booking_owner(pg_temp.ph(30), pg_temp.mail('nobody')) is null
    and public.calcom_booking_owner(pg_temp.ph(30), null) is null
    and public.calcom_booking_owner(pg_temp.ph(31), pg_temp.mail('nobody')) = pg_temp.fx('e1')
    and public.calcom_booking_owner(pg_temp.ph(99), pg_temp.mail('e1')) = pg_temp.fx('e1')
    and public.calcom_booking_owner(null, pg_temp.mail('e1')) = pg_temp.fx('e1')
    and public.calcom_booking_owner(null, pg_temp.mail('qq')) is null
    and public.calcom_booking_owner(pg_temp.ph(34), null) = pg_temp.fx('d2')
    and public.calcom_booking_owner(pg_temp.ph(35), pg_temp.mail('nobody')) is null
    and public.calcom_booking_owner(null, null) is null,
  'M1 the owner rule: the one customer with the phone (whatever the email); a shared phone narrowed by the email inbox (Gmail dots, +tag, googlemail), else no one; no one with the phone: the one with the email; two with it: no one; a deleted customer is no one');
select pg_temp.check(pg_temp.st('s1') = 'upcoming ' || pg_temp.iso(pg_temp.sg(pg_temp.today() + 2, '10:00'))
    and pg_temp.st('s2') = 'upcoming ' || pg_temp.iso(pg_temp.sg(pg_temp.today() + 3, '10:00'))
    and pg_temp.st('e1') = 'upcoming ' || pg_temp.iso(pg_temp.sg(pg_temp.today() + 2, '10:00'))
    and pg_temp.st('q1') = 'none' and pg_temp.st('q2') = 'none'
    and pg_temp.st('d2') = 'upcoming ' || pg_temp.iso(pg_temp.sg(pg_temp.today() + 2, '10:00'))
    and pg_temp.st('d1') is null and pg_temp.st('d3') is null
    and pg_temp.st('g1') = 'none' and pg_temp.st('g2') = 'none',
  'M2 on the rows: each household member gets their own booking, the shared-phone booking that decides nothing shows for neither; the email alone; two with one email: neither; the living customer, not the deleted ones (who have no row)');
-- M3 merged: the kept record takes the twins' booking (an Owner merges, as the Customers page does).
do $$ begin
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform public.merge_customer_records(pg_temp.fx('g1'), pg_temp.fx('g2'), 'T480 fixture twins', gen_random_uuid());
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
end $$;
select pg_temp.check((select deleted_at is not null from public.customers where id = pg_temp.fx('g2'))
    and pg_temp.st('g1') = 'upcoming ' || pg_temp.iso(pg_temp.sg(pg_temp.today() + 2, '10:00')) and pg_temp.st('g2') is null,
  'M3 twins on one phone, merged: the kept record shows the booking (the merged one is deleted); nothing in the merge changed');
-- M3b-M11 a merged record's booking follows the merge (the Owner, 29 Oct 2026): only when no customer in use holds
-- the booking's phone (nor, for the email step, its inbox), the deleted records holding it are followed along the
-- merges merge_customer_records wrote (the kept record's customers_merged row) to the customers in use they ended
-- in; exactly one is the person. Every merge as the Customers page does it (an Owner, merge_customer_records). Tier
-- 1 of a referrer with a portal login (aff3), so both screens are read.
do $$ declare v uuid; r uuid; aff uuid; k record; begin
  insert into public.customers (full_name, phone) values ('T480 Merge Referrer', pg_temp.ph(88)) returning id into r;
  perform pg_temp.putx('mr', r);
  insert into public.customer_affiliates (customer_id, status, store_id, activated_at)
  values (r, 'active', (select s.id from public.stores s where s.code = 'T480' || pg_temp.tx('sfx')), now()) returning id into aff;
  insert into public.affiliate_accounts (auth_user_id, customer_id, affiliate_id, status) values (pg_temp.fx('aff3'), r, aff, 'claimed');
  for k in select * from (values
      ('mk1', 'T480 Merge Kept', 89, 'mk1', true), ('md1', 'T480 Merge Dup', 90, null, true),
      ('mk3', 'T480 Mail Kept', 91, 'mk3', true), ('md3', 'T480 Mail Dup', 92, null, true),
      ('chc', 'T480 Chain C', 93, null, true), ('chb', 'T480 Chain B', 94, null, false), ('cha', 'T480 Chain A', 95, null, false),
      ('tk1', 'T480 Two Kept One', 96, null, true), ('tk2', 'T480 Two Kept Two', 97, null, true),
      ('td1', 'T480 Two Dup One', 100, null, false), ('td2', 'T480 Two Dup Two', 100, null, false),
      ('dx', 'T480 Deleted By Delete', 102, null, false),
      ('rk', 'T480 Restore Kept', 103, null, true), ('rx', 'T480 Restore Dup', 104, null, false),
      ('wk', 'T480 Wins Kept', 105, null, true), ('wy', 'T480 Wins Dup', 106, null, false), ('wz', 'T480 Wins Holder', 106, null, false),
      ('ek', 'T480 Email Kept', 107, 'ek', true), ('ed', 'T480 Email Dup', 108, 'ed', false)) x(key, name, n, mail, tier1) loop
    insert into public.customers (full_name, phone, email, referred_by)
    values (k.name, pg_temp.ph(k.n), case when k.mail is not null then pg_temp.mail(k.mail) end, case when k.tier1 then r end)
    returning id into v;
    perform pg_temp.putx(k.key, v);
  end loop;
end $$;
select pg_temp.ingest(pg_temp.ev('BOOKING_CREATED', now() - interval '1 hour', pg_temp.bk(x.tag, pg_temp.sg(pg_temp.today() + x.d, '14:00'), x.phone, x.email)))
  from (values ('mb1', 3, pg_temp.ph(90), pg_temp.mail('stranger')),   -- the duplicate's phone, a stranger's email
               ('mb2', 4, pg_temp.ph(90), null),                       -- the duplicate's phone, no email (as a calendar-fill row)
               ('mb3', 5, pg_temp.ph(92), pg_temp.mail('mk3')),        -- the duplicate's phone, the kept record's email
               ('mc1', 6, pg_temp.ph(95), null),                       -- chain A's phone
               ('mc2', 7, pg_temp.ph(94), null),                       -- chain B's phone
               ('mt1', 6, pg_temp.ph(100), null),                      -- the two duplicates' shared phone
               ('mx1', 6, pg_temp.ph(102), null),                      -- a record deleted with Delete
               ('mr1', 6, pg_temp.ph(104), null),                      -- merged, restored, deleted again later
               ('mw1', 6, pg_temp.ph(106), null),                      -- a customer in use holds it too
               ('me1', 8, pg_temp.ph(109), pg_temp.mail('ed')),        -- a phone nobody has, the merged record's email
               ('mp1', 9, pg_temp.ph(90), pg_temp.mail('ed'))) x(tag, d, phone, email);  -- a merged phone and another merged email
select pg_temp.put('m3b_before', concat_ws(' | ', pg_temp.st('md1'), pg_temp.st('mk1'), pg_temp.st('md3'), pg_temp.st('mk3')));
do $$ begin
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform public.merge_customer_records(pg_temp.fx('mk1'), pg_temp.fx('md1'), 'T480 fixture merge, another phone', gen_random_uuid());
  perform public.merge_customer_records(pg_temp.fx('mk3'), pg_temp.fx('md3'), 'T480 fixture merge, the kept email', gen_random_uuid());
  perform public.merge_customer_records(pg_temp.fx('chb'), pg_temp.fx('cha'), 'T480 fixture chain, A into B', gen_random_uuid());
  perform public.merge_customer_records(pg_temp.fx('chc'), pg_temp.fx('chb'), 'T480 fixture chain, B into C', gen_random_uuid());
  perform public.merge_customer_records(pg_temp.fx('tk1'), pg_temp.fx('td1'), 'T480 fixture two kept, one', gen_random_uuid());
  perform public.merge_customer_records(pg_temp.fx('tk2'), pg_temp.fx('td2'), 'T480 fixture two kept, two', gen_random_uuid());
  perform public.merge_customer_records(pg_temp.fx('rk'), pg_temp.fx('rx'), 'T480 fixture merge, then restored', gen_random_uuid());
  perform public.restore_customer_with_phone(pg_temp.fx('rx'), null, 'T480 fixture restore');
  perform public.merge_customer_records(pg_temp.fx('wk'), pg_temp.fx('wy'), 'T480 fixture merge, the phone still held', gen_random_uuid());
  perform public.merge_customer_records(pg_temp.fx('ek'), pg_temp.fx('ed'), 'T480 fixture merge, by email', gen_random_uuid());
  perform public.delete_customer(pg_temp.fx('dx'), 'T480 Deleted By Delete', 'T480 fixture delete');
  perform public.delete_customer(pg_temp.fx('rx'), 'T480 Restore Dup', 'T480 fixture delete after restore');
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
end $$;
-- The restored duplicate was deleted again on a later day: Delete stamps that day's moment (inside this one test
-- transaction now() is still the merge's moment, so the later stamp is written as Delete would have written it).
update public.customers set deleted_at = now() + interval '1 day' where id = pg_temp.fx('rx');
select pg_temp.put('m_dl', pg_temp.try_as('manager', format('select public.customer_downline_visits(%L::uuid)::text', pg_temp.fx('mr'))));
select pg_temp.put('m_net', pg_temp.try_as('aff3', 'select public.affiliate_portal_network()::text'));
select pg_temp.check(pg_temp.tx('m3b_before') = concat_ws(' | ', 'upcoming ' || pg_temp.iso(pg_temp.sg(pg_temp.today() + 3, '14:00')), 'none',
                                                         'upcoming ' || pg_temp.iso(pg_temp.sg(pg_temp.today() + 5, '14:00')), 'none')
    and (select count(*) from public.customers where id in (pg_temp.fx('md1'), pg_temp.fx('md3')) and deleted_at is not null) = 2
    and public.calcom_booking_owner(pg_temp.ph(90), pg_temp.mail('stranger')) = pg_temp.fx('mk1')
    and public.calcom_booking_owner(pg_temp.ph(90), null) = pg_temp.fx('mk1')
    and public.calcom_booking_owner(pg_temp.ph(92), pg_temp.mail('mk3')) = pg_temp.fx('mk3')
    and pg_temp.st('mk1') = 'upcoming ' || pg_temp.iso(pg_temp.sg(pg_temp.today() + 3, '14:00'))
    and pg_temp.st('mk3') = 'upcoming ' || pg_temp.iso(pg_temp.sg(pg_temp.today() + 5, '14:00'))
    and pg_temp.st('md1') is null,
  'M3b a merge whose kept record has another phone and email: the duplicate''s bookings (with a stranger''s email, or none, as a calendar-fill row) showed on the duplicate before it and on the kept record after it: ' || pg_temp.tx('m3b_before'));
select pg_temp.check(public.calcom_booking_owner(pg_temp.ph(95), null) = pg_temp.fx('chc')
    and public.calcom_booking_owner(pg_temp.ph(94), null) = pg_temp.fx('chc')
    and pg_temp.st('chc') = 'upcoming ' || pg_temp.iso(pg_temp.sg(pg_temp.today() + 6, '14:00')),
  'M5 a chain (A merged into B, then B into C): bookings made with A''s or B''s phone are C''s, the next one shown');
select pg_temp.check(public.calcom_booking_owner(pg_temp.ph(100), null) is null
    and pg_temp.st('tk1') = 'none' and pg_temp.st('tk2') = 'none',
  'M6 two duplicates on one phone merged into two different customers: the booking is no one''s');
select pg_temp.check((select deleted_at is not null from public.customers where id = pg_temp.fx('dx'))
    and public.calcom_booking_owner(pg_temp.ph(102), null) is null,
  'M7 a record deleted with Delete (no merge) is not followed: its booking is no one''s');
select pg_temp.check((select deleted_at is not null from public.customers where id = pg_temp.fx('rx'))
    and exists (select 1 from public.audit_logs l where l.action = 'customers_merged' and l.record_id = pg_temp.fx('rk')
                                                     and l.new_data ->> 'merged_from' = pg_temp.fx('rx')::text)
    and public.calcom_booking_owner(pg_temp.ph(104), null) is null and pg_temp.st('rk') = 'none',
  'M8 a record merged, restored, and deleted again later with Delete is not followed (its deletion is not the merge)');
select pg_temp.check(public.calcom_booking_owner(pg_temp.ph(106), null) = pg_temp.fx('wz') and pg_temp.st('wk') = 'none',
  'M9 a customer in use holding the phone wins over a merged record that held it too');
select pg_temp.check(public.calcom_booking_owner(pg_temp.ph(109), pg_temp.mail('ed')) = pg_temp.fx('ek')
    and pg_temp.st('ek') = 'upcoming ' || pg_temp.iso(pg_temp.sg(pg_temp.today() + 8, '14:00'))
    and public.calcom_booking_owner(pg_temp.ph(90), pg_temp.mail('ed')) = pg_temp.fx('mk1'),
  'M10 no one holds the phone, in use or merged: the merged record''s email inbox leads to the kept record; a merged phone decides before a merged email');
select pg_temp.check(pg_temp.state(pg_temp.tx('m_dl')) = 'ok' and pg_temp.state(pg_temp.tx('m_net')) = 'ok'
    and pg_temp.rows_by(pg_temp.body(pg_temp.tx('m_dl'))::jsonb, 'tier1', 'name') = jsonb_build_object(
          'T480 Merge Kept', jsonb_build_array('upcoming', to_jsonb(pg_temp.sg(pg_temp.today() + 3, '14:00')) #>> '{}'),
          'T480 Mail Kept', jsonb_build_array('upcoming', to_jsonb(pg_temp.sg(pg_temp.today() + 5, '14:00')) #>> '{}'),
          'T480 Chain C', jsonb_build_array('upcoming', to_jsonb(pg_temp.sg(pg_temp.today() + 6, '14:00')) #>> '{}'),
          'T480 Two Kept One', jsonb_build_array('none', null), 'T480 Two Kept Two', jsonb_build_array('none', null),
          'T480 Restore Kept', jsonb_build_array('none', null), 'T480 Wins Kept', jsonb_build_array('none', null),
          'T480 Email Kept', jsonb_build_array('upcoming', to_jsonb(pg_temp.sg(pg_temp.today() + 8, '14:00')) #>> '{}'))
    and pg_temp.rows_by(pg_temp.body(pg_temp.tx('m_net'))::jsonb, 'tier1', 'customer_name')
        = pg_temp.rows_by(pg_temp.body(pg_temp.tx('m_dl'))::jsonb, 'tier1', 'name'),
  'M11 both screens: the Downline and My Network show each kept record the bookings that followed its merges, and none where the rule finds no one');
-- M4 a customer made after the booking.
do $$ declare v uuid; begin
  insert into public.customers (full_name, phone) values ('T480 Made Later', pg_temp.ph(37)) returning id into v;
  perform pg_temp.putx('l1', v);
end $$;
select pg_temp.check(pg_temp.st('l1') = 'upcoming ' || pg_temp.iso(pg_temp.sg(pg_temp.today() + 2, '10:00')),
  'M4 a customer made after the booking arrived shows it');

-- ═════ C Came: a purchase at the Adelphi centre that day (the Owner, 29 Oct 2026) ═════
-- Tier 1 of a referrer with a portal login (aff4): each booked two days ago at 11 am (Singapore) and either bought
-- that day (an invoice of the kind its key says) or not; no survey but csurv's (the control: a visit still counts).
do $$ declare v uuid; r uuid; aff uuid; k record; begin
  insert into public.customers (full_name, phone) values ('T480 Came Referrer', pg_temp.ph(110)) returning id into r;
  perform pg_temp.putx('cr', r);
  insert into public.customer_affiliates (customer_id, status, store_id, activated_at)
  values (r, 'active', (select s.id from public.stores s where s.code = 'T480' || pg_temp.tx('sfx')), now()) returning id into aff;
  insert into public.affiliate_accounts (auth_user_id, customer_id, affiliate_id, status) values (pg_temp.fx('aff4'), r, aff, 'claimed');
  for k in select x.key, x.n from (values ('cpaid', 111), ('cpart', 112), ('cfoc', 113), ('crreq', 114), ('crefd', 115),
      ('cdraft', 116), ('cunpd', 117), ('ccxlr', 118), ('ccxl', 119), ('cvan', 120), ('cweb', 121), ('cvip', 122), ('cgst', 123),
      ('cbdn', 124), ('cbdz', 125), ('cbdx', 126), ('cbdy', 127), ('cday', 128), ('cdel', 129), ('cnone', 130), ('csurv', 131)) x(key, n) loop
    insert into public.customers (full_name, phone, referred_by) values ('T480 Came ' || k.key, pg_temp.ph(k.n), r) returning id into v;
    perform pg_temp.putx(k.key, v);
  end loop;
end $$;
-- The invoices (made by the Owner), and the online and event orders that name three of them.
do $$
declare d date := pg_temp.today() - 2; x record; v uuid;
begin
  for x in select * from (values
      ('cpaid', 'adelphi', 'paid', d, pg_temp.sg(d, '12:00'), false),
      ('cpart', 'adelphi', 'partially_paid', d, pg_temp.sg(d, '12:00'), false),
      ('cfoc', 'adelphi', 'completed_foc', d, pg_temp.sg(d, '12:00'), false),
      ('crreq', 'adelphi', 'refund_requested', d, pg_temp.sg(d, '12:00'), false),
      ('crefd', 'adelphi', 'refunded', d, pg_temp.sg(d, '12:00'), false),
      ('cdraft', 'adelphi', 'draft', d, pg_temp.sg(d, '12:00'), false),
      ('cunpd', 'adelphi', 'unpaid', d, pg_temp.sg(d, '12:00'), false),
      ('ccxlr', 'adelphi', 'cancellation_requested', d, pg_temp.sg(d, '12:00'), false),
      ('ccxl', 'adelphi', 'cancelled', d, pg_temp.sg(d, '12:00'), false),
      ('cvan', 'van', 'paid', d, pg_temp.sg(d, '12:00'), false),
      ('cweb', 'adelphi', 'paid', d, pg_temp.sg(d, '12:00'), false),
      ('cvip', 'adelphi', 'paid', d, pg_temp.sg(d, '12:00'), false),
      ('cgst', 'adelphi', 'paid', d, pg_temp.sg(d, '12:00'), false),
      ('cbdn', 'adelphi', 'paid', null::date, pg_temp.sg(d, '23:30'), false),      -- no business date: made 11.30 pm that day
      ('cbdz', 'adelphi', 'paid', null::date, pg_temp.sg(d + 1, '00:30'), false),  -- no business date: made 12.30 am the next day (that day in UTC)
      ('cbdx', 'adelphi', 'paid', d - 1, pg_temp.sg(d, '12:00'), false),           -- made that day, dated the day before
      ('cbdy', 'adelphi', 'paid', d, pg_temp.sg(d + 1, '12:00'), false),           -- dated that day, made the next
      ('cday', 'adelphi', 'paid', d + 1, pg_temp.sg(d + 1, '12:00'), false),       -- another day
      ('cdel', 'adelphi', 'paid', d, pg_temp.sg(d, '12:00'), true)) y(k, store, st, bd, made, del) loop
    insert into public.invoices (invoice_no, store_id, customer_id, created_by, status, subtotal, total_amount, paid_amount,
                                 business_date, created_at, deleted_at, notes)
    values ('T480-' || pg_temp.tx('sfx') || '-' || x.k, pg_temp.fx(x.store), pg_temp.fx(x.k), pg_temp.fx('owner'), x.st::public.invoice_status,
            100, 100, case x.st when 'paid' then 100 when 'partially_paid' then 40 else 0 end, x.bd, x.made,
            case when x.del then now() end, 'T480 fixture')
    returning id into v;
    perform pg_temp.putx('inv_' || x.k, v);
  end loop;
  insert into public.health_surveys (survey_no, customer_id, full_name, phone, source, submitted_at, remarks_condition)
  values ('HS-T480-' || pg_temp.tx('sfx') || '-csurv', pg_temp.fx('csurv'), 'T480 Came csurv', '+61255500000', 'consultant',
          pg_temp.sg(d, '15:00'), 'T480 answer');
end $$;
-- The order rows only need to name the invoice: written as the server would, without their other records.
set local session_replication_role = replica;
insert into public.web_orders (channel, stripe_session_id, livemode, status, ticket, quantity, unit_amount_cents, amount_total_cents,
                               early_bird, buyer_name, checkout_opened_at, paid_at, invoice_id)
values ('t480', 'cs_t480_' || pg_temp.tx('sfx'), false, 'invoiced', 'fixture', 1, 0, 0, false, 'T480 Web Buyer', now(), now(), pg_temp.fx('inv_cweb'));
insert into public.event_vip_order_people (order_ref, person_id, position, invoice_id) values (gen_random_uuid(), gen_random_uuid(), 1, pg_temp.fx('inv_cvip'));
insert into public.event_guests (event_id, name, source, invoice_id, invoice_item_id)
values (gen_random_uuid(), 'T480 Came guest', 'ticket', pg_temp.fx('inv_cgst'), gen_random_uuid());
set local session_replication_role = origin;
select pg_temp.ingest(pg_temp.ev('BOOKING_CREATED', now() - interval '5 days', pg_temp.bk('cb_' || x.k, pg_temp.sg(pg_temp.today() - 2, '11:00'), pg_temp.ph(x.n), null)))
  from (values ('cpaid', 111), ('cpart', 112), ('cfoc', 113), ('crreq', 114), ('crefd', 115),
      ('cdraft', 116), ('cunpd', 117), ('ccxlr', 118), ('ccxl', 119), ('cvan', 120), ('cweb', 121), ('cvip', 122), ('cgst', 123),
      ('cbdn', 124), ('cbdz', 125), ('cbdx', 126), ('cbdy', 127), ('cday', 128), ('cdel', 129), ('cnone', 130), ('csurv', 131)) x(k, n);
create function pg_temp.states(keys text[]) returns text language sql as
$$ select string_agg(k || '=' || coalesce(pg_temp.st0(k), '?'), ' ' order by o) from unnest(keys) with ordinality x(k, o) $$;
select pg_temp.check(pg_temp.states(array['cpaid', 'cpart', 'cfoc', 'crreq', 'crefd'])
                     = 'cpaid=came cpart=came cfoc=came crreq=came crefd=came',
  'C1 an invoice at the Adelphi centre that day, its money or FOC settled, makes the booking came: paid, partially paid, FOC, refund requested, refunded: '
  || pg_temp.states(array['cpaid', 'cpart', 'cfoc', 'crreq', 'crefd']));
select pg_temp.check(pg_temp.states(array['cdraft', 'cunpd', 'ccxlr', 'ccxl']) = 'cdraft=miss cunpd=miss ccxlr=miss ccxl=miss',
  'C2 a draft, unpaid, cancellation-requested or cancelled invoice does not: ' || pg_temp.states(array['cdraft', 'cunpd', 'ccxlr', 'ccxl']));
select pg_temp.check(pg_temp.states(array['cvan', 'cweb', 'cvip', 'cgst']) = 'cvan=miss cweb=miss cvip=miss cgst=miss',
  'C3 the Van & RoadShow does not, nor an online order (a web order), a VIP order or an event guest''s invoice at the centre: '
  || pg_temp.states(array['cvan', 'cweb', 'cvip', 'cgst']));
select pg_temp.check(pg_temp.states(array['cbdn', 'cbdz', 'cbdx', 'cbdy']) = 'cbdn=came cbdz=miss cbdx=miss cbdy=came',
  'C4 the day is the invoice''s business date, else the Singapore date it was made (11.30 pm counts, 12.30 am the next day does not, though it is that day in UTC): '
  || pg_temp.states(array['cbdn', 'cbdz', 'cbdx', 'cbdy']));
select pg_temp.check(pg_temp.states(array['cday', 'cdel', 'cnone', 'csurv']) = 'cday=miss cdel=miss cnone=miss csurv=came',
  'C5 a purchase on another day, a deleted invoice and none: miss; a consultant''s survey that day (the visit rule) still makes it came: '
  || pg_temp.states(array['cday', 'cdel', 'cnone', 'csurv']));
select pg_temp.put('c_dl', pg_temp.try_as('manager', format('select public.customer_downline_visits(%L::uuid)::text', pg_temp.fx('cr'))));
select pg_temp.put('c_net', pg_temp.try_as('aff4', 'select public.affiliate_portal_network()::text'));
select pg_temp.check(pg_temp.state(pg_temp.tx('c_dl')) = 'ok' and pg_temp.state(pg_temp.tx('c_net')) = 'ok'
    and (select string_agg(replace(r ->> 'name', 'T480 Came ', '') || '=' || (r ->> 'booking_state'), ' ' order by r ->> 'name')
           from jsonb_array_elements(pg_temp.body(pg_temp.tx('c_dl'))::jsonb -> 'tier1') r)
        = 'cbdn=came cbdx=miss cbdy=came cbdz=miss ccxl=miss ccxlr=miss cday=miss cdel=miss cdraft=miss cfoc=came cgst=miss cnone=miss cpaid=came '
          || 'cpart=came crefd=came crreq=came csurv=came cunpd=miss cvan=miss cvip=miss cweb=miss'
    and (select bool_and((r ->> 'booking_at')::timestamptz = pg_temp.sg(pg_temp.today() - 2, '11:00'))
           from jsonb_array_elements(pg_temp.body(pg_temp.tx('c_dl'))::jsonb -> 'tier1') r)
    and pg_temp.rows_by(pg_temp.body(pg_temp.tx('c_net'))::jsonb, 'tier1', 'customer_name')
        = pg_temp.rows_by(pg_temp.body(pg_temp.tx('c_dl'))::jsonb, 'tier1', 'name'),
  'C6 both screens: the Downline and My Network show each one''s booking as came or Miss by the same rule');
select pg_temp.check((select jsonb_agg(jsonb_build_array(r ->> 'name', r -> 'visited', r -> 'first_visit_on') order by r ->> 'name')
                        from jsonb_array_elements(pg_temp.body(pg_temp.tx('c_dl'))::jsonb -> 'tier1') r
                       where r ->> 'name' in ('T480 Came cpaid', 'T480 Came cbdy', 'T480 Came csurv'))
                     = jsonb_build_array(jsonb_build_array('T480 Came cbdy', false, null), jsonb_build_array('T480 Came cpaid', false, null),
                                         jsonb_build_array('T480 Came csurv', true, to_jsonb((pg_temp.today() - 2)::text)))
    and not exists (select 1 from public.customer_centre_visits() v where v.customer_id in (pg_temp.fx('cpaid'), pg_temp.fx('cbdy'), pg_temp.fx('cfoc'))),
  'C7 a purchase makes no visit: Visited and First visit (and the visit rule) are as they were; only the booking''s state reads it');

-- ═════ S States ═════
-- The network's bookings: u1 a missed one and an upcoming one; t1 today just after midnight; c1, m1 two
-- days ago (c1 visited that day, m1 the day before); x1 cancelled; r1 rescheduled away to a booking that is not theirs.
select pg_temp.ingest(pg_temp.ev('BOOKING_CREATED', now() - interval '10 days', pg_temp.bk(x.tag, x.at, pg_temp.ph(x.n), null)))
  from (values ('su1old', pg_temp.sg(pg_temp.today() - 5, '10:00'), 2), ('su1', pg_temp.sg(pg_temp.today() + 3, '15:30'), 2),
               ('su1late', pg_temp.sg(pg_temp.today() + 30, '10:00'), 2),
               ('st1', pg_temp.sg(pg_temp.today(), '00:00:01'), 3), ('sc1', pg_temp.sg(pg_temp.today() - 2, '11:00'), 4),
               ('sm1', pg_temp.sg(pg_temp.today() - 2, '11:00'), 5), ('sx1', pg_temp.sg(pg_temp.today() + 1, '11:00'), 7),
               ('sr1', pg_temp.sg(pg_temp.today() + 1, '12:00'), 8),
               ('su2', pg_temp.sg(pg_temp.today() + 1, '19:59'), 11), ('sc2', pg_temp.sg(pg_temp.today() - 2, '20:00'), 12),
               ('sm2', pg_temp.sg(pg_temp.today() - 1, '23:59'), 13),
               ('so1', pg_temp.sg(pg_temp.today() + 2, '10:00'), 21),
               ('sk1', pg_temp.sg(pg_temp.today() + 20, '14:00'), 40), ('sk2', pg_temp.sg(pg_temp.today() + 20, '14:00'), 41)) x(tag, at, n);
select pg_temp.ingest(pg_temp.ev('BOOKING_CANCELLED', now() - interval '1 day', jsonb_build_object('uid', pg_temp.uid('sx1'))));
select pg_temp.ingest(pg_temp.ev('BOOKING_RESCHEDULED', now() - interval '1 day',
  pg_temp.bk('sr1new', pg_temp.sg(pg_temp.today() + 2, '12:00'), pg_temp.ph(98), null, jsonb_build_object('rescheduleUid', pg_temp.uid('sr1')))));
select pg_temp.check(pg_temp.st('u1') = 'upcoming ' || pg_temp.iso(pg_temp.sg(pg_temp.today() + 3, '15:30'))
    and pg_temp.st('t1') = 'upcoming ' || pg_temp.iso(pg_temp.sg(pg_temp.today(), '00:00:01'))
    and pg_temp.st('c1') = 'came ' || pg_temp.iso(pg_temp.sg(pg_temp.today() - 2, '11:00'))
    and pg_temp.st('m1') = 'miss ' || pg_temp.iso(pg_temp.sg(pg_temp.today() - 2, '11:00'))
    and pg_temp.st('n1') = 'none' and pg_temp.st('x1') = 'none' and pg_temp.st('r1') = 'none'
    and pg_temp.st('u2') = 'upcoming ' || pg_temp.iso(pg_temp.sg(pg_temp.today() + 1, '19:59'))
    and pg_temp.st('c2') = 'came ' || pg_temp.iso(pg_temp.sg(pg_temp.today() - 2, '20:00'))
    and pg_temp.st('m2') = 'miss ' || pg_temp.iso(pg_temp.sg(pg_temp.today() - 1, '23:59')),
  'S1 the next booking beats the last (u1: its next one, not its missed one or a later one); today''s, though its time has passed, is upcoming; a past one with a visit that Singapore day is came (c2: 8 pm, its visit at 11.30 pm), without one miss (m1 visited the day before); none; cancelled only and rescheduled away only: none');
select pg_temp.check(pg_temp.st0('k1', pg_temp.today() + 19) = 'upcoming' and pg_temp.st0('k1', pg_temp.today() + 20) = 'upcoming'
    and pg_temp.st0('k1', pg_temp.today() + 21) = 'miss' and pg_temp.st0('k2', pg_temp.today() + 20) = 'upcoming'
    and pg_temp.st0('k2', pg_temp.today() + 21) = 'came' and pg_temp.st0('k2', pg_temp.today() + 60) = 'came'
    and pg_temp.st0('n1', pg_temp.today() + 21) = 'none',
  'S2 a miss only once the day is over: upcoming the day before and on the day, miss from the next Singapore day; with a visit that day, came');
select pg_temp.check((select count(*) from public.calcom_customer_bookings(array[pg_temp.fx('u1'), pg_temp.fx('d1'), gen_random_uuid(), null])) = 1
    and (select count(*) from public.calcom_customer_bookings(null)) = 0,
  'S3 the state rule answers one row per customer in use asked about (not a deleted or unknown id), none for none');

-- ═════ R The two screens' rows ═════
select pg_temp.put('dl', pg_temp.try_as('manager', format('select public.customer_downline_visits(%L::uuid)::text', pg_temp.fx('rae'))));
select pg_temp.put('net', pg_temp.try_as('aff', 'select public.affiliate_portal_network()::text'));
select pg_temp.check(pg_temp.state(pg_temp.tx('dl')) = 'ok'
    and pg_temp.rows_by(pg_temp.body(pg_temp.tx('dl'))::jsonb, 'tier1', 'name') = jsonb_build_object(
          'T480 Tier1 u1', jsonb_build_array('upcoming', to_jsonb(pg_temp.sg(pg_temp.today() + 3, '15:30')) #>> '{}'),
          'T480 Tier1 t1', jsonb_build_array('upcoming', to_jsonb(pg_temp.sg(pg_temp.today(), '00:00:01')) #>> '{}'),
          'T480 Tier1 c1', jsonb_build_array('came', to_jsonb(pg_temp.sg(pg_temp.today() - 2, '11:00')) #>> '{}'),
          'T480 Tier1 m1', jsonb_build_array('miss', to_jsonb(pg_temp.sg(pg_temp.today() - 2, '11:00')) #>> '{}'),
          'T480 Tier1 n1', jsonb_build_array('none', null), 'T480 Tier1 x1', jsonb_build_array('none', null),
          'T480 Tier1 r1', jsonb_build_array('none', null))
    and pg_temp.rows_by(pg_temp.body(pg_temp.tx('dl'))::jsonb, 'tier2', 'name') = jsonb_build_object(
          'T480 Tier2 u2', jsonb_build_array('upcoming', to_jsonb(pg_temp.sg(pg_temp.today() + 1, '19:59')) #>> '{}'),
          'T480 Tier2 c2', jsonb_build_array('came', to_jsonb(pg_temp.sg(pg_temp.today() - 2, '20:00')) #>> '{}'),
          'T480 Tier2 m2', jsonb_build_array('miss', to_jsonb(pg_temp.sg(pg_temp.today() - 1, '23:59')) #>> '{}'),
          'T480 Tier2 n2', jsonb_build_array('none', null)),
  'R1 the Downline: every Tier 1 and Tier 2 row has booking_at and booking_state as the state rule says');
select pg_temp.check(pg_temp.state(pg_temp.tx('net')) = 'ok'
    and pg_temp.rows_by(pg_temp.body(pg_temp.tx('net'))::jsonb, 'tier1', 'customer_name')
        = pg_temp.rows_by(pg_temp.body(pg_temp.tx('dl'))::jsonb, 'tier1', 'name')
    and pg_temp.rows_by(pg_temp.body(pg_temp.tx('net'))::jsonb, 'tier2', 'customer_name')
        = pg_temp.rows_by(pg_temp.body(pg_temp.tx('dl'))::jsonb, 'tier2', 'name'),
  'R2 My Network (the affiliate''s own): the same booking and state on every Tier 1 and Tier 2 row as the Downline');
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
    and (select array_agg(k order by k) from jsonb_object_keys(pg_temp.body(pg_temp.tx('net'))::jsonb) k) = array['tier1', 'tier2'],
  'R3 each row has its old keys and the two new ones, nothing else; the answers'' top-level keys are as they were');
select pg_temp.check(pg_temp.body(pg_temp.tx('net')) !~ ('cb480' || pg_temp.tx('sfx')) and pg_temp.body(pg_temp.tx('net')) !~ '\+6125550'
    and pg_temp.body(pg_temp.tx('net')) !~* '@example|fixture|whatsapp|"free"',
  'R4 the portal''s answer holds no booking uid, phone, email, answer, title or event type (only the start and the state)');
\if :{?skip_install}
\else
select pg_temp.check(pg_temp.state(pg_temp.tx('pre_dl')) = 'ok' and pg_temp.state(pg_temp.tx('pre_net')) = 'ok'
    and (select jsonb_build_object('customer_id', d -> 'customer_id', 'name', d -> 'name', 'phone', d -> 'phone',
                  'tier1', (select coalesce(jsonb_agg(r - 'booking_at' - 'booking_state' order by n), '[]') from jsonb_array_elements(d -> 'tier1') with ordinality t(r, n)),
                  'tier2', (select coalesce(jsonb_agg(r - 'booking_at' - 'booking_state' order by n), '[]') from jsonb_array_elements(d -> 'tier2') with ordinality t(r, n)))
           from (select pg_temp.body(pg_temp.tx('dl'))::jsonb as d) x)
        = pg_temp.body(pg_temp.tx('pre_dl'))::jsonb
    and (select jsonb_build_object(
                  'tier1', (select coalesce(jsonb_agg(r - 'booking_at' - 'booking_state' order by (r - 'booking_at' - 'booking_state')::text), '[]') from jsonb_array_elements(d -> 'tier1') r),
                  'tier2', (select coalesce(jsonb_agg(r - 'booking_at' - 'booking_state' order by (r - 'booking_at' - 'booking_state')::text), '[]') from jsonb_array_elements(d -> 'tier2') r))
           from (select pg_temp.body(pg_temp.tx('net'))::jsonb as d) x)
        = (select jsonb_build_object(
                  'tier1', (select coalesce(jsonb_agg(r order by r::text), '[]') from jsonb_array_elements(d -> 'tier1') r),
                  'tier2', (select coalesce(jsonb_agg(r order by r::text), '[]') from jsonb_array_elements(d -> 'tier2') r))
             from (select pg_temp.body(pg_temp.tx('pre_net'))::jsonb as d) x),
  'R5 without its two new keys every row is word for word what it was before 480, and the Downline''s rows in the same order (the portal''s rows, which tie on their order, the same set)');
\endif

-- ═════ P Who may ═════
select pg_temp.check(pg_temp.try_as(w.k, format('select public.customer_downline_visits(%L::uuid)::text', pg_temp.fx('rae'))) = pg_temp.tx('dl'),
  format('P1 %s gets exactly the Manager''s Downline, bookings included', w.label))
  from (values ('owner', 'the Owner'), ('admin', 'the Admin'), ('staff', 'Staff'), ('service', 'the service role'), ('server', 'the server')) w(k, label);
select pg_temp.check(pg_temp.try_as(w.k, format('select public.customer_downline_visits(%L::uuid)::text', pg_temp.fx('rae'))) = w.answer,
  format('P2 %s is refused the Downline: %s', w.label, w.answer))
  from (values ('invman', 'an Inventory Manager', '42501' || chr(9) || 'Your role cannot do this.'),
               ('inactive', 'a deactivated employee', '42501' || chr(9) || 'Only active Energia staff can do this.'),
               ('nostaff', 'a login with no profile', '42501' || chr(9) || 'Only active Energia staff can do this.'),
               ('aff', 'an affiliate portal login', '42501' || chr(9) || 'Only active Energia staff can do this.')) w(k, label, answer);
select pg_temp.check(pg_temp.state(pg_temp.try_as('anon', format('select public.customer_downline_visits(%L::uuid)::text', pg_temp.fx('rae')))) = '42501'
    and pg_temp.state(pg_temp.try_as('anon', 'select public.affiliate_portal_network()::text')) = '42501',
  'P3 signed out: refused both (no grant)');
select pg_temp.check(pg_temp.try_as('aff2', 'select public.affiliate_portal_network()::text') like 'ok' || chr(9) || '%'
    and pg_temp.rows_by(pg_temp.body(pg_temp.try_as('aff2', 'select public.affiliate_portal_network()::text'))::jsonb, 'tier1', 'customer_name')
        = jsonb_build_object('T480 Other Friend', jsonb_build_array('upcoming', to_jsonb(pg_temp.sg(pg_temp.today() + 2, '10:00')) #>> '{}'))
    and pg_temp.body(pg_temp.try_as('aff2', 'select public.affiliate_portal_network()::text')) !~ 'T480 Tier'
    and pg_temp.try_as('staff', 'select public.affiliate_portal_network()::text') = 'P0001' || chr(9) || 'Not an affiliate account',
  'P4 another affiliate sees only their own network''s bookings; a staff login is not an affiliate');
select pg_temp.check(pg_temp.state(pg_temp.try_as('service', x.q)) = 'ok'
    and pg_temp.state(pg_temp.try_as('owner', x.q)) = '42501' and pg_temp.state(pg_temp.try_as('staff', x.q)) = '42501'
    and pg_temp.state(pg_temp.try_as('aff', x.q)) = '42501' and pg_temp.state(pg_temp.try_as('anon', x.q)) = '42501',
  'P5 ' || x.fn || ': the service role may; an Owner, Staff, an affiliate and signed out may not (42501)')
  from (values ('calcom_booking_ingest', format('select public.calcom_booking_ingest(%L::jsonb)::text', pg_temp.ev('PING', now(), '{}'))),
               ('calcom_booking_backfill', 'select public.calcom_booking_backfill(''[]''::jsonb, now() - interval ''1 day'', now(), now())::text'),
               ('calcom_booking_owner', format('select public.calcom_booking_owner(%L, null)::text', pg_temp.ph(30))),
               ('calcom_customer_bookings', format('select count(*)::text from public.calcom_customer_bookings(array[%L::uuid])', pg_temp.fx('u1')))) x(fn, q);
select pg_temp.check(pg_temp.state(pg_temp.try_as('service', x.q)) = '42501' and pg_temp.state(pg_temp.try_as('owner', x.q)) = '42501'
    and pg_temp.state(pg_temp.try_as('anon', x.q)) = '42501',
  'P6 ' || x.fn || ': no one''s endpoint (the service role, an Owner and signed out refused)')
  from (values ('calcom_booking_apply', 'select public.calcom_booking_apply(''cb480p'', ''active'', now(), null, null, null, null, null, now(), ''BOOKING_CREATED'')'),
               ('calcom_parse_time', 'select public.calcom_parse_time(''2026-10-29T00:00:00Z'')::text')) x(fn, q);
select pg_temp.check(pg_temp.state(pg_temp.try_as('anon', 'select count(*)::text from public.calcom_bookings')) = '42501'
    and pg_temp.state(pg_temp.try_as('owner', 'select count(*)::text from public.calcom_bookings')) = '42501'
    and pg_temp.state(pg_temp.try_as('aff', 'select count(*)::text from public.calcom_bookings')) = '42501'
    and pg_temp.try_as('service', 'select count(*)::text from public.calcom_bookings') = 'ok' || chr(9) || (select count(*)::text from public.calcom_bookings)
    and pg_temp.state(pg_temp.try_as('service', 'insert into public.calcom_bookings (uid, status, source) values (''cb480q'', ''cancelled'', ''backfill'') returning uid')) = '42501'
    and pg_temp.state(pg_temp.try_as('service', 'update public.calcom_bookings set status = status returning uid')) = '42501',
  'P7 the table: signed out, an Owner and an affiliate cannot read it; the service role reads it and cannot write it');

-- ═════ G md5s, grants and shape ═════
select pg_temp.check((select array_agg(f.fn || ' ' || f.md5 order by f.fn) from pg_temp.fn_md5s() f
                       where f.fn like 'calcom%' or f.fn in ('customer_downline_visits(uuid)', 'affiliate_portal_network()'))
    = array['affiliate_portal_network() d1c387fb852392da041b5d8207655879',
            'calcom_booking_apply(text,text,timestamp with time zone,timestamp with time zone,bigint,text,text,text,timestamp with time zone,text,text) 844d56ae966ca4e1e633e070e0195256',
            'calcom_booking_backfill(jsonb,timestamp with time zone,timestamp with time zone,timestamp with time zone,boolean,text[],boolean) b68af462ad32de7af3f8b98a8491a7e1',
            'calcom_booking_ingest(jsonb) 55d6b6b8b7509911a225f494313212d9',
            'calcom_booking_owner(text,text) 959a5a8280ac20155068b3fa9aae73f3',
            'calcom_customer_bookings(uuid[],date) 2e651a5d2367ba26bfd9e8e00d95823e',
            'calcom_parse_time(text) 773399bc477ceb3476dd84a6a9251f2d',
            'customer_downline_visits(uuid) ea3f28ea932506eda6937fa687298d6d'],
  'G1 the eight functions are at 480''s AFTER md5s');
select pg_temp.check((select array_agg(p.proname || ' ' || (select array_agg(x::text order by x::text) from unnest(p.proacl) x)::text order by p.proname)
                        from pg_proc p where p.pronamespace = 'public'::regnamespace
                         and (p.proname like 'calcom%' or p.proname in ('customer_downline_visits', 'affiliate_portal_network')))
    = array['affiliate_portal_network {authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres}',
            'calcom_booking_apply {postgres=X/postgres}',
            'calcom_booking_backfill {postgres=X/postgres,service_role=X/postgres}',
            'calcom_booking_ingest {postgres=X/postgres,service_role=X/postgres}',
            'calcom_booking_owner {postgres=X/postgres,service_role=X/postgres}',
            'calcom_customer_bookings {postgres=X/postgres,service_role=X/postgres}',
            'calcom_parse_time {postgres=X/postgres}',
            'customer_downline_visits {authenticated=X/postgres,postgres=X/postgres,service_role=X/postgres}']
    and (select bool_and(p.prosecdef and p.proconfig = array['search_path=public'])
           from pg_proc p where p.pronamespace = 'public'::regnamespace
            and p.proname in ('calcom_booking_ingest', 'calcom_booking_backfill', 'calcom_booking_owner', 'calcom_customer_bookings',
                              'customer_downline_visits', 'affiliate_portal_network'))
    and (select bool_and(not p.prosecdef and p.proconfig = array['search_path=public'])
           from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('calcom_booking_apply', 'calcom_parse_time')),
  'G2 grants: the two screens as before (signed in and the service role); ingest, backfill, owner and the state rule the service role''s; apply and parse_time no one''s; definer functions with search_path public');
select pg_temp.check((select array_agg(f.fn || ' ' || f.md5 order by f.fn) from pg_temp.fn_md5s() f
                       where f.fn in ('normalize_customer_phone(text)', 'customer_email_match_key(text)', 'customer_centre_visit_days()',
                                      'customer_centre_visits()', 'require_active_staff(text[])', 'current_affiliate_customer_id()',
                                      'merge_customer_records(uuid,uuid,text,uuid)', 'write_audit(text,uuid,text,jsonb,jsonb)'))
    = array['current_affiliate_customer_id() 51695acf5f26ce3918d6003d0c980b0f', 'customer_centre_visit_days() 2129857d6ff9f29dcf2cbccc9f13e5bc',
            'customer_centre_visits() c07a5a0cbbf52ba45e5dc911b20002da', 'customer_email_match_key(text) be468815c9626fff1728e2cfcd484b66',
            'merge_customer_records(uuid,uuid,text,uuid) ba05c2b1fb4c0e14d369c01d06a635b0',
            'normalize_customer_phone(text) b2bfac910e0c9eff402ba44e19750bee', 'require_active_staff(text[]) 877b3aa74cea559881979bb161c450e2',
            'write_audit(text,uuid,text,jsonb,jsonb) b194f839993670c5b5dd28e934c2a829'],
  'G3 what it relies on is unchanged (the visit rule, the phone and email readers, the role checks, what a merge writes)');
select pg_temp.check((select c.relrowsecurity from pg_class c where c.oid = 'public.calcom_bookings'::regclass)
    and not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'calcom_bookings')
    and (select array_agg(i order by i) from pg_indexes, lateral (select indexname::text as i) x where schemaname = 'public' and tablename = 'calcom_bookings')
        = array['calcom_bookings_email_key_idx', 'calcom_bookings_phone_key_idx', 'calcom_bookings_pkey']
    and pg_get_indexdef('public.idx_customers_email_match_key'::regclass) like '%customer_email_match_key(email)) WHERE ((deleted_at IS NULL) AND (email IS NOT NULL))'
    and pg_get_constraintdef((select c.oid from pg_constraint c where c.conrelid = 'public.calcom_bookings'::regclass and c.conname = 'calcom_bookings_event_check'))
        = 'CHECK (((last_event_at IS NOT NULL) AND ((source = ''webhook''::text) = (last_trigger IS NOT NULL))))'
    and pg_get_indexdef('public.idx_customers_deleted_phone_norm'::regclass) like '%(normalize_customer_phone(phone)) WHERE (deleted_at IS NOT NULL)'
    and pg_get_indexdef('public.idx_customers_deleted_email_match_key'::regclass)
        like '%(customer_email_match_key(email)) WHERE ((deleted_at IS NOT NULL) AND (email IS NOT NULL))',
  'G4 the table: row-level security on, no policy; its three indexes; every row timed (the webhook''s rows with their trigger); customers'' email-inbox index, and the deleted records'' phone and inbox indexes (a merged record''s booking)');

-- ═════ N 480 twice; a changed function or table is refused ═════
\if :{?skip_install}
\else
select pg_temp.check(not exists (select 1 from m480 m full join m480b b on b.fn = m.fn where m.fn is null or b.fn is null or b.md5 <> m.md5),
  'N1 running 480 a second time changed no function');
select pg_temp.check((select coalesce(array_agg(m.fn order by m.fn), '{}') from m480 m left join b480 b on b.fn = m.fn where b.fn is null or b.md5 <> m.md5)
                     = array['affiliate_portal_network()',
                             'calcom_booking_apply(text,text,timestamp with time zone,timestamp with time zone,bigint,text,text,text,timestamp with time zone,text,text)',
                             'calcom_booking_backfill(jsonb,timestamp with time zone,timestamp with time zone,timestamp with time zone,boolean,text[],boolean)',
                             'calcom_booking_ingest(jsonb)', 'calcom_booking_owner(text,text)',
                             'calcom_customer_bookings(uuid[],date)', 'calcom_parse_time(text)', 'customer_downline_visits(uuid)']
    and not exists (select 1 from b480 b left join m480 m on m.fn = b.fn where m.fn is null)
    and (select count(*) from m480) = (select count(*) from b480) + 6,
  'N2 its first run changed the two functions and added the six (no other function changed, none dropped)');
select pg_temp.check((select after1 - 'calcom_bookings' = before and after1 ->> 'calcom_bookings' = '0' from r480),
  'N3 480''s self-test left no row (every table of public and auth counts the same before and after it; the new table empty)');
select pg_temp.check((select seq_after1 = seq_before from r480),
  'N4 and moved no sequence: ' || (select coalesce(string_agg(k, ', '), 'none') from r480, jsonb_each(seq_after1) e(k, v) where seq_before -> k is distinct from v));
\endif
-- A function changed since (a comment added to customer_downline_visits): 480 refuses, changing nothing.
savepoint n5;
do $$ begin
  perform set_config('search_path', 'public', true);
  execute regexp_replace(pg_get_functiondef('public.customer_downline_visits(uuid)'::regprocedure),
                         'AS \$function\$', 'AS $function$ -- changed by the 480 suite');
end $$;
reset search_path;
\echo 'N5: 480 is expected to refuse here (an ERROR is printed):'
\set ON_ERROR_STOP off
\ir ../../../supabase/480_downline_and_network_show_calcom_booking.sql
\set ON_ERROR_STOP on
\set n5_msg :LAST_ERROR_MESSAGE
rollback to savepoint n5;
select pg_temp.check(:'n5_msg' like '480: public.customer_downline_visits(uuid) is neither production''s version of 29 Oct 2026 nor this file''s%Re-read it and re-test before applying.',
  'N5 a changed customer_downline_visits is refused (all undone): ' || :'n5_msg');
-- A table of another shape: refused.
savepoint n6;
alter table public.calcom_bookings add column attendee_name text;
\echo 'N6: 480 is expected to refuse here (an ERROR is printed):'
\set ON_ERROR_STOP off
\ir ../../../supabase/480_downline_and_network_show_calcom_booking.sql
\set ON_ERROR_STOP on
\set n6_msg :LAST_ERROR_MESSAGE
rollback to savepoint n6;
select pg_temp.check(:'n6_msg' like '480: public.calcom_bookings exists and is not this migration''s%',
  'N6 a calcom_bookings table of another shape is refused: ' || :'n6_msg');
select pg_temp.check((select md5 from pg_temp.fn_md5s() where fn = 'customer_downline_visits(uuid)') = 'ea3f28ea932506eda6937fa687298d6d'
    and not exists (select 1 from pg_attribute where attrelid = 'public.calcom_bookings'::regclass and attname = 'attendee_name'),
  'N7 after the refusals the function and the table are 480''s');

-- The Adelphi centre is found by its code: 480 refuses unless exactly one store in use has it (renamed, or deleted).
savepoint n8;
update public.stores set code = code || '-T480' where code = 'RETAIL-ADELPHI';
\echo 'N8: 480 is expected to refuse here (an ERROR is printed):'
\set ON_ERROR_STOP off
\ir ../../../supabase/480_downline_and_network_show_calcom_booking.sql
\set ON_ERROR_STOP on
\set n8_msg :LAST_ERROR_MESSAGE
rollback to savepoint n8;
savepoint n9;
update public.stores set deleted_at = now() where code = 'RETAIL-ADELPHI';
\echo 'N8: 480 is expected to refuse here too (an ERROR is printed):'
\set ON_ERROR_STOP off
\ir ../../../supabase/480_downline_and_network_show_calcom_booking.sql
\set ON_ERROR_STOP on
\set n9_msg :LAST_ERROR_MESSAGE
rollback to savepoint n9;
select pg_temp.check(:'n8_msg' = '480: exactly one store in use must be coded RETAIL-ADELPHI (the Adelphi centre); found 0'
    and :'n9_msg' = '480: exactly one store in use must be coded RETAIL-ADELPHI (the Adelphi centre); found 0'
    and (select count(*) from public.stores where code = 'RETAIL-ADELPHI' and deleted_at is null) = 1,
  'N8 with the Adelphi store renamed, or deleted, 480 is refused (all undone): ' || :'n8_msg');

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All 480 checks passed.';
end $$;
rollback;
