-- The referral page tells somebody already registered about their upcoming booking, and shows its
-- time and its booking id only when the phone AND the email both match it (549; the user, 27 Nov
-- 2026: "Phone + email must match (Recommended)").
--
-- Every lookup is made as the page makes it: signed out (the anon role; a signed-in login where
-- said), through public.referral_booking_lookup(code, phone, email), with the request headers
-- PostgREST hands over (request.headers; a sender is the address in cf-connecting-ip).
--
--   N  No upcoming active booking on the phone: {"state":"none"}; a code padded with spaces and a
--      link that is not accepting are still valid codes; a phone typed with spaces is the number.
--   E  A booking, and the email blank, empty, malformed or another one: {"state":"needs_email"}
--      and nothing else; a booking with no email of its own: needs_email whatever is typed.
--   B  The booking's own email (case and spaces around it ignored, as customer_email_match_key
--      reads it): {"state":"booked","start_at","end_at","uid"} exactly, times in UTC ISO 8601;
--      end_at null when the booking has none.
--   G  A 'gcal:...' booking: booked with uid null.
--   C  Cancelled and rescheduled bookings are ignored (as cal.com leaves them: no phone; and, with
--      the table's checks lifted for the test, even when they still carry the phone and email).
--   D  The Singapore date: a booking at 23:59:59 yesterday (Singapore) is ignored; one at 00:00:00
--      today (Singapore), already past, still counts all day.
--   O  The earliest of two (and by uid when they start together); the email must be THAT
--      booking's: the later booking's email is needs_email.
--   I  Invalid: an unknown, empty, deleted affiliate's or deleted customer's code; a phone that is
--      not a valid number (empty, letters, null). Never raised. Recorded, the bad phone left out.
--   S  One sender: 10 lookups an hour, whatever each was answered; the 11th is try_later for a
--      booked number with its right email too; the refusal recorded once an hour (hammering adds
--      nothing); another address answered; invalid past the limit answered but not recorded;
--      invalid within it counts; an hour later answered again.
--   V  IPv6: one /64 is one sender (an address in it written another way shares it), another /64
--      is not; ::ffff:a.b.c.d is that IPv4 address; x-forwarded-for alone is no sender; the key is
--      exactly the one affiliate_referral_signup keeps for the same address (529).
--   P  One phone: 5 lookups an hour from any senders (wrong emails), then try_later, the right
--      email too; recorded once an hour; a sender's refusal does not count for the phone; an hour
--      later answered again.
--   L  The sender's and the phone's advisory locks are held after a lookup (so two cannot both take
--      the last place).
--   R  anon, authenticated and the service role may call it, PUBLIC not; a signed-in login gets the
--      same answers; no API role reads, writes or uses the table or its sequence (a select as anon
--      or a login is refused 42501); 543's rule: no TRUNCATE, REFERENCES or TRIGGER; row level
--      security on, no policy; owner postgres, SECURITY DEFINER, search_path public, pg_temp; 549's
--      AFTER md5; the table refuses a sender key that is not a hash and an unknown outcome; 529's
--      salt unchanged.
--   B0 (install mode) 549 refuses on a database whose functions are not production's after 547.
--   U  (install mode) scripts/affiliate-signup/undo-549.sql drops both and puts the function
--      fingerprint back; it refuses when the function is not 549's; a second undo refuses; 549
--      again makes the same.
--   M  (install mode) 549 a second time refuses.
--
-- Disposable local database only; everything is rolled back. Every name is invented ("Testing
-- ..."), emails @example.invalid, phones +61 491 570 5nn, uids t549_..., addresses from the
-- documentation ranges (192.0.2.0/24, 198.51.100.0/24, 203.0.113.0/24, 2001:db8::/32). Run it on a
-- copy of production after 547 (it applies 549, then again); with -v skip_install=1 where 549 is in
-- (B0, U and M skipped).
--   psql -X -v ON_ERROR_STOP=1 -f scripts/affiliate-signup/tests/referral-booking-lookup-549.sql
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '300s';
create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create function pg_temp.fp() returns text language sql as
$$ select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) || '/' || count(*)
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' $$;
set local search_path = public;
create temp table fp0 as select pg_temp.fp() as f;
select to_regprocedure('public.referral_booking_lookup(text,text,text)') is not null as had549 \gset
\if :{?skip_install}
\if :had549
\else
\echo 549 is not in: run without -v skip_install
select 1/0;
\endif
\set mode skip
\elif :had549
\echo 549 is already in: run with -v skip_install=1
select 1/0;
\else
\set mode install
\endif
select :'mode' = 'install' as by_us \gset

\if :by_us
-- ═════ B0 549 refuses on other functions ═════
savepoint b0;
create function public.t549_stray() returns int language sql as 'select 1';
\set ON_ERROR_STOP off
\ir ../../../supabase/549_referral_page_shows_an_existing_booking.sql
\set ON_ERROR_STOP on
rollback to savepoint b0;
select pg_temp.check(:'LAST_ERROR_MESSAGE' like '549: the functions are not production''s after 547%'
                     and to_regprocedure('public.referral_booking_lookup(text,text,text)') is null
                     and to_regclass('public.referral_booking_lookups') is null,
  'B0 549 refuses on functions other than production''s after 547 and makes nothing: ' || :'LAST_ERROR_MESSAGE');
select pg_temp.check((select f from fp0) = '73d175b2e8d324bb524127497fe3d02b/1470',
  'B1 installed on production''s functions after 547 (73d175b2.../1470): ' || (select f from fp0));
\ir ../../../supabase/549_referral_page_shows_an_existing_booking.sql
\endif
set local search_path = public;

-- ═════ Helpers ═════
create temp table tx(k text primary key, v text);
create function pg_temp.tx(key text) returns text language sql as $$ select v from tx where k = key $$;
create function pg_temp.put(key text, val text) returns void language sql as
$$ insert into tx values (key, val) on conflict (k) do update set v = excluded.v $$;
create function pg_temp.ph(n int) returns text language sql as $$ select '+61491570' || (500 + n)::text $$;
create function pg_temp.mail(key text) returns text language sql as
$$ select 't549-' || lower(key) || '-' || pg_temp.tx('sfx') || '@example.invalid' $$;
create function pg_temp.code(key text) returns text language sql as $$ select pg_temp.tx('code:' || key) $$;
create function pg_temp.hdr(ip text) returns text language sql as $$ select json_build_object('cf-connecting-ip', ip)::text $$;
-- 529's sender key for an address (IPv4) or a /64 ('net::/64'): read as the owner, never printed.
create function pg_temp.h(k text) returns text language plpgsql as
$$declare v text; begin
  select salt into v from public.referral_sender_salt where id;
  return encode(sha256(convert_to(v || '|' || k, 'UTF8')), 'hex');
end$$;
-- A lookup as the page makes it: this role (anon unless said), these request headers (null: none).
create function pg_temp.q(tag text, headers text, code text, phone text, email text default null, p_role text default 'anon')
returns jsonb language plpgsql as
$$declare r jsonb; begin
  perform set_config('request.headers', coalesce(headers, ''), true);
  perform set_config('request.jwt.claim.role', p_role, true);
  perform set_config('request.jwt.claims', json_build_object('role', p_role)::text, true);
  execute format('set local role %I', p_role);
  begin
    r := public.referral_booking_lookup(code, phone, email);
  exception when others then r := jsonb_build_object('error', sqlstate || ' ' || sqlerrm);
  end;
  execute 'reset role';
  perform set_config('request.headers', '', true);
  perform set_config('request.jwt.claims', '', true);
  perform pg_temp.put('q:' || tag, coalesce(r::text, 'null'));
  return r;
end$$;
create function pg_temp.a(tag text) returns jsonb language sql as $$ select pg_temp.tx('q:' || tag)::jsonb $$;
create function pg_temp.st(s text) returns jsonb language sql as $$ select jsonb_build_object('state', s) $$;
-- The lookups recorded for a sender key, a phone, an outcome (null: any).
create function pg_temp.lk(p_sender text default null, p_phone text default null, p_outcome text default null) returns int language sql as
$$ select count(*)::int from public.referral_booking_lookups l
    where (p_sender is null or l.sender_key = p_sender) and (p_phone is null or l.phone_key = p_phone)
      and (p_outcome is null or l.outcome = p_outcome) $$;
-- A booking as 480 keeps it (filled in, not from a webhook).
create function pg_temp.bk(uid text, start_at timestamptz, phone text, email text, status text default 'active',
                           end_at timestamptz default 'infinity') returns void language sql as
$$ insert into public.calcom_bookings(uid, start_at, end_at, status, phone_key, email_key, source, last_event_at)
   values (uid, start_at, case when end_at = 'infinity' then start_at + interval '1 hour' else end_at end, status,
           case when status = 'active' then public.normalize_customer_phone(phone) end,
           case when status = 'active' then public.customer_email_match_key(email) end, 'backfill', now()) $$;
-- The UTC text the answer must carry for a Singapore day and time.
create function pg_temp.utc(d date, sg_time time) returns text language sql as
$$ select to_char((d + sg_time) - interval '8 hours', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') $$;
create function pg_temp.sgday(d date, sg_time time) returns timestamptz language sql as
$$ select (d + sg_time) at time zone 'Asia/Singapore' $$;
create function pg_temp.booked(tag text, uid text, d date, t0 time, t1 time) returns boolean language sql as
$$ select pg_temp.a(tag) = jsonb_build_object('state', 'booked', 'start_at', pg_temp.utc(d, t0),
                                              'end_at', case when t1 is not null then pg_temp.utc(d, t1) end, 'uid', uid) $$;

-- ═════ Fixtures ═════
do $$ begin insert into tx values ('sfx', lower(substr(md5(random()::text || clock_timestamp()::text), 1, 6))); end $$;
select pg_temp.check(not exists (select 1 from public.calcom_bookings b where b.phone_key like '+614915705__' or b.uid like 't549%' or b.uid like 'gcal:t549%')
    and not exists (select 1 from public.referral_booking_lookups l where l.phone_key like '+614915705__')
    and not exists (select 1 from public.customers c where public.normalize_customer_phone(c.phone) like '+614915705__'),
  'P0 no booking, lookup or customer uses the test phones (+61491570500..599)');
create temp table salt0 as select md5(salt) as m from public.referral_sender_salt;
do $$ declare c uuid; k text; i int := 0; begin
  -- A: accepting; Z: suspended (still a valid code); X: the affiliate record deleted; Y: its customer deleted.
  foreach k in array array['A', 'Z', 'X', 'Y'] loop
    i := i + 1;
    insert into customers(full_name, phone, email) values ('Testing Referrer' || k, pg_temp.ph(90 + i), pg_temp.mail('ref' || k))
      returning id into c;
    insert into customer_affiliates(customer_id, status, activated_at, referral_code, manually_suspended, deleted_at)
    values (c, 'active', now() - interval '30 days', upper('T549' || k || pg_temp.tx('sfx')), k = 'Z',
            case when k = 'X' then now() end);
    if k = 'Y' then update customers set deleted_at = now() where id = c; end if;
    insert into tx values ('code:' || k, upper('T549' || k || pg_temp.tx('sfx')));
  end loop;
end $$;
select (public.sg_today() + 10) as d10, (public.sg_today() + 3) as d3, (public.sg_today() + 5) as d5,
       public.sg_today() as d0 \gset

-- ═════ N none ═════
select pg_temp.q('n1', null, pg_temp.code('A'), pg_temp.ph(1));
select pg_temp.q('n2', null, '  ' || pg_temp.code('A') || ' ', '+61 491 570 501', 'someone@example.invalid');
select pg_temp.q('n3', null, pg_temp.code('Z'), pg_temp.ph(1));
select pg_temp.check(pg_temp.a('n1') = pg_temp.st('none') and pg_temp.a('n2') = pg_temp.st('none') and pg_temp.a('n3') = pg_temp.st('none'),
  'N1 no booking on the phone: none (a padded code, a phone with spaces, a link not accepting): ' || pg_temp.a('n1')::text);
select pg_temp.check(pg_temp.lk(null, pg_temp.ph(1), 'none') = 3 and pg_temp.lk(null, pg_temp.ph(1)) = 3,
  'N2 each recorded as none with the phone');

-- ═════ E needs_email, B booked ═════
select pg_temp.bk('t549_e' || pg_temp.tx('sfx'), pg_temp.sgday(:'d10', '10:00'), pg_temp.ph(2), 'Testing.Booker@Example.invalid');
select pg_temp.q('e1', null, pg_temp.code('A'), pg_temp.ph(2));
select pg_temp.q('e2', null, pg_temp.code('A'), pg_temp.ph(2), '   ');
select pg_temp.q('e3', null, pg_temp.code('A'), pg_temp.ph(2), 'testing.booker@example');
select pg_temp.q('e4', null, pg_temp.code('A'), pg_temp.ph(2), 'other.person@example.invalid');
select pg_temp.check(pg_temp.a('e1') = pg_temp.st('needs_email') and pg_temp.a('e2') = pg_temp.st('needs_email')
                     and pg_temp.a('e3') = pg_temp.st('needs_email') and pg_temp.a('e4') = pg_temp.st('needs_email'),
  'E1 a booking and a blank, empty, malformed or other email: needs_email and nothing else: '
  || pg_temp.a('e1')::text || ' ' || pg_temp.a('e3')::text || ' ' || pg_temp.a('e4')::text);
select pg_temp.bk('t549_b' || pg_temp.tx('sfx'), pg_temp.sgday(:'d10', '10:00'), pg_temp.ph(3), 'Testing.Booker@Example.invalid');
select pg_temp.q('b1', null, pg_temp.code('A'), pg_temp.ph(3), 'testing.booker@example.invalid');
select pg_temp.q('b2', null, pg_temp.code('A'), pg_temp.ph(3), '  TESTING.BOOKER@example.INVALID  ');
select pg_temp.check(pg_temp.booked('b1', 't549_b' || pg_temp.tx('sfx'), :'d10', '10:00', '11:00')
                     and pg_temp.booked('b2', 't549_b' || pg_temp.tx('sfx'), :'d10', '10:00', '11:00'),
  'B1 the booking''s own email (case and spaces ignored): booked, start and end in UTC, its uid: ' || pg_temp.a('b2')::text);
select pg_temp.check((select array_agg(k order by k) from jsonb_object_keys(pg_temp.a('b1')) k) = array['end_at', 'start_at', 'state', 'uid'],
  'B2 booked carries state, start_at, end_at and uid only');
select pg_temp.bk('t549_n' || pg_temp.tx('sfx'), pg_temp.sgday(:'d3', '15:30'), pg_temp.ph(4), 'testing.noend@example.invalid', 'active', null);
select pg_temp.q('b3', null, pg_temp.code('A'), pg_temp.ph(4), 'testing.noend@example.invalid');
select pg_temp.check(pg_temp.booked('b3', 't549_n' || pg_temp.tx('sfx'), :'d3', '15:30', null) and pg_temp.a('b3') ? 'end_at',
  'B3 a booking without an end: booked with end_at null: ' || pg_temp.a('b3')::text);
select pg_temp.bk('t549_x' || pg_temp.tx('sfx'), pg_temp.sgday(:'d3', '09:00'), pg_temp.ph(5), null);
select pg_temp.q('b4', null, pg_temp.code('A'), pg_temp.ph(5), 'testing.any@example.invalid');
select pg_temp.check(pg_temp.a('b4') = pg_temp.st('needs_email'), 'B4 a booking with no email of its own: needs_email whatever is typed');
select pg_temp.check(pg_temp.lk(null, pg_temp.ph(3), 'booked') = 2 and pg_temp.lk(null, pg_temp.ph(2), 'needs_email') = 4,
  'B5 booked and needs_email recorded with the phone');

-- ═════ G a calendar fill-in ═════
select pg_temp.bk('gcal:t549_g' || pg_temp.tx('sfx'), pg_temp.sgday(:'d5', '14:00'), pg_temp.ph(6), 'testing.gcal@example.invalid');
select pg_temp.q('g1', null, pg_temp.code('A'), pg_temp.ph(6), 'testing.gcal@example.invalid');
select pg_temp.check(pg_temp.booked('g1', null, :'d5', '14:00', '15:00') and pg_temp.a('g1') ? 'uid',
  'G1 a gcal: booking: booked with uid null: ' || pg_temp.a('g1')::text);

-- ═════ C cancelled and rescheduled ═════
select pg_temp.bk('t549_c' || pg_temp.tx('sfx'), pg_temp.sgday(:'d3', '10:00'), pg_temp.ph(7), 'testing.cancel@example.invalid', 'cancelled');
select pg_temp.bk('t549_r' || pg_temp.tx('sfx'), pg_temp.sgday(:'d3', '11:00'), pg_temp.ph(7), 'testing.cancel@example.invalid', 'rescheduled');
select pg_temp.q('c1', null, pg_temp.code('A'), pg_temp.ph(7), 'testing.cancel@example.invalid');
select pg_temp.check(pg_temp.a('c1') = pg_temp.st('none'), 'C1 cancelled and rescheduled bookings (as cal.com leaves them): none');
savepoint c2;
alter table public.calcom_bookings drop constraint calcom_bookings_phone_key_check, drop constraint calcom_bookings_email_key_check;
insert into public.calcom_bookings(uid, start_at, end_at, status, phone_key, email_key, source, last_event_at)
values ('t549_c2' || pg_temp.tx('sfx'), pg_temp.sgday(:'d3', '08:00'), null, 'cancelled', pg_temp.ph(8), 'testing.both@example.invalid', 'backfill', now()),
       ('t549_r2' || pg_temp.tx('sfx'), pg_temp.sgday(:'d3', '08:30'), null, 'rescheduled', pg_temp.ph(8), 'testing.both@example.invalid', 'backfill', now());
select pg_temp.q('c2', null, pg_temp.code('A'), pg_temp.ph(8), 'testing.both@example.invalid');
select pg_temp.bk('t549_a2' || pg_temp.tx('sfx'), pg_temp.sgday(:'d5', '12:00'), pg_temp.ph(8), 'testing.both@example.invalid');
select pg_temp.q('c3', null, pg_temp.code('A'), pg_temp.ph(8), 'testing.both@example.invalid');
-- (the savepoint takes the temporary rows back too, so the answers are kept in psql variables)
select (pg_temp.a('c2') = pg_temp.st('none') and pg_temp.booked('c3', 't549_a2' || pg_temp.tx('sfx'), :'d5', '12:00', '13:00')) as c_ok,
       pg_temp.a('c2')::text || ' ' || pg_temp.a('c3')::text as c_seen \gset
rollback to savepoint c2;
select pg_temp.check(:'c_ok'::boolean,
  'C2 a cancelled or rescheduled row that still carries the phone and email is ignored; the later active booking is the one: ' || :'c_seen');

-- ═════ D the Singapore date ═════
select pg_temp.bk('t549_y' || pg_temp.tx('sfx'), pg_temp.sgday(:'d0', '00:00') - interval '1 second', pg_temp.ph(9), 'testing.day@example.invalid');
select pg_temp.q('d1', null, pg_temp.code('A'), pg_temp.ph(9), 'testing.day@example.invalid');
select pg_temp.bk('t549_t' || pg_temp.tx('sfx'), pg_temp.sgday(:'d0', '00:00'), pg_temp.ph(9), 'testing.day@example.invalid');
select pg_temp.q('d2', null, pg_temp.code('A'), pg_temp.ph(9), 'testing.day@example.invalid');
select pg_temp.check(pg_temp.a('d1') = pg_temp.st('none'), 'D1 a booking at 23:59:59 yesterday (Singapore) is not upcoming: ' || pg_temp.a('d1')::text);
select pg_temp.check(pg_temp.booked('d2', 't549_t' || pg_temp.tx('sfx'), :'d0', '00:00', '01:00'),
  'D2 one at 00:00:00 today (Singapore), already past, still counts all day (yesterday''s, earlier, is passed over): ' || pg_temp.a('d2')::text);

-- ═════ O the earliest ═════
select pg_temp.bk('t549_o9' || pg_temp.tx('sfx'), pg_temp.sgday(:'d5', '10:00'), pg_temp.ph(10), 'testing.late@example.invalid');
select pg_temp.bk('t549_o2' || pg_temp.tx('sfx'), pg_temp.sgday(:'d3', '10:00'), pg_temp.ph(10), 'testing.early@example.invalid');
select pg_temp.q('o1', null, pg_temp.code('A'), pg_temp.ph(10), 'testing.early@example.invalid');
select pg_temp.q('o2', null, pg_temp.code('A'), pg_temp.ph(10), 'testing.late@example.invalid');
select pg_temp.check(pg_temp.booked('o1', 't549_o2' || pg_temp.tx('sfx'), :'d3', '10:00', '11:00') and pg_temp.a('o2') = pg_temp.st('needs_email'),
  'O1 the earliest of two is the one; the later booking''s email is needs_email: ' || pg_temp.a('o1')::text || ' ' || pg_temp.a('o2')::text);
select pg_temp.bk('t549_ob' || pg_temp.tx('sfx'), pg_temp.sgday(:'d3', '16:00'), pg_temp.ph(11), 'testing.tie@example.invalid');
select pg_temp.bk('t549_oa' || pg_temp.tx('sfx'), pg_temp.sgday(:'d3', '16:00'), pg_temp.ph(11), 'testing.tie@example.invalid');
select pg_temp.q('o3', null, pg_temp.code('A'), pg_temp.ph(11), 'testing.tie@example.invalid');
select pg_temp.check(pg_temp.booked('o3', 't549_oa' || pg_temp.tx('sfx'), :'d3', '16:00', '17:00'),
  'O2 two at the same time: the first by uid');

-- ═════ I invalid ═════
select pg_temp.q('i1', null, 'T549NOSUCHCODE', pg_temp.ph(12), 'testing.booker@example.invalid');
select pg_temp.q('i2', null, '', pg_temp.ph(12));
select pg_temp.q('i3', null, null, pg_temp.ph(12));
select pg_temp.q('i4', null, pg_temp.code('X'), pg_temp.ph(12), 'testing.booker@example.invalid');
select pg_temp.q('i5', null, pg_temp.code('Y'), pg_temp.ph(12), 'testing.booker@example.invalid');
select pg_temp.q('i6', null, pg_temp.code('A'), '', 'testing.booker@example.invalid');
select pg_temp.q('i7', null, pg_temp.code('A'), 'call me', 'testing.booker@example.invalid');
select pg_temp.q('i8', null, pg_temp.code('A'), null, null);
select pg_temp.q('i9', null, pg_temp.code('A'), '12', null);
select pg_temp.check(bool_and(pg_temp.a(t) = pg_temp.st('invalid')),
  'I1 an unknown, empty or missing code, a deleted affiliate''s or deleted customer''s code, and a phone that is not valid: invalid, never raised: '
  || string_agg(t || '=' || pg_temp.a(t)::text, ' ' order by t))
  from unnest(array['i1', 'i2', 'i3', 'i4', 'i5', 'i6', 'i7', 'i8', 'i9']) t;
select pg_temp.check(pg_temp.lk(null, pg_temp.ph(12), 'invalid') = 5
                     and (select count(*) from public.referral_booking_lookups where outcome = 'invalid' and phone_key is null and sender_key is null
                            and created_at = now()) >= 4,
  'I2 each recorded as invalid: a bad code with the phone, a bad phone without one');

-- ═════ S one sender ═════
do $$ declare i int; begin
  for i in 1 .. 4 loop perform pg_temp.q('s' || i, pg_temp.hdr('203.0.113.49'), pg_temp.code('A'), pg_temp.ph(20 + i)); end loop;
  perform pg_temp.q('s5', pg_temp.hdr('203.0.113.49'), pg_temp.code('A'), pg_temp.ph(2), 'wrong@example.invalid');
  perform pg_temp.q('s6', pg_temp.hdr('203.0.113.49'), 'T549NOSUCHCODE', pg_temp.ph(25));
  perform pg_temp.q('s7', pg_temp.hdr('203.0.113.49'), pg_temp.code('A'), 'x');
  for i in 8 .. 10 loop perform pg_temp.q('s' || i, pg_temp.hdr('203.0.113.49'), pg_temp.code('A'), pg_temp.ph(20 + i)); end loop;
end $$;
select pg_temp.check(pg_temp.a('s1') = pg_temp.st('none') and pg_temp.a('s5') = pg_temp.st('needs_email')
                     and pg_temp.a('s6') = pg_temp.st('invalid') and pg_temp.a('s7') = pg_temp.st('invalid') and pg_temp.a('s10') = pg_temp.st('none')
                     and pg_temp.lk(pg_temp.h('203.0.113.49')) = 10,
  'S1 ten lookups from 203.0.113.49, each answered as usual and recorded with the sender (' || pg_temp.lk(pg_temp.h('203.0.113.49')) || ')');
select pg_temp.q('s11', pg_temp.hdr('203.0.113.49'), pg_temp.code('A'), pg_temp.ph(3), 'testing.booker@example.invalid');
select pg_temp.q('s12', pg_temp.hdr('203.0.113.49'), pg_temp.code('A'), pg_temp.ph(31));
select pg_temp.q('s13', pg_temp.hdr('203.0.113.49'), pg_temp.code('A'), pg_temp.ph(3), 'testing.booker@example.invalid');
select pg_temp.check(pg_temp.a('s11') = pg_temp.st('try_later') and pg_temp.a('s12') = pg_temp.st('try_later') and pg_temp.a('s13') = pg_temp.st('try_later'),
  'S2 the 11th and after: try_later, for a booked number with its right email as for one with nothing: ' || pg_temp.a('s11')::text);
select pg_temp.check(pg_temp.lk(pg_temp.h('203.0.113.49'), null, 'try_later') = 1 and pg_temp.lk(pg_temp.h('203.0.113.49')) = 11
                     and (select phone_key from public.referral_booking_lookups where sender_key = pg_temp.h('203.0.113.49') and outcome = 'try_later') is null,
  'S3 the refusal is recorded once an hour (hammering adds nothing), without a phone');
select pg_temp.q('s14', pg_temp.hdr('203.0.113.49'), 'T549NOSUCHCODE', pg_temp.ph(32));
select pg_temp.q('s15', pg_temp.hdr('203.0.113.49'), pg_temp.code('A'), 'nope');
select pg_temp.check(pg_temp.a('s14') = pg_temp.st('invalid') and pg_temp.a('s15') = pg_temp.st('invalid') and pg_temp.lk(pg_temp.h('203.0.113.49')) = 11,
  'S4 invalid input past the limit is answered invalid but not recorded');
select pg_temp.q('s16', pg_temp.hdr('203.0.113.50'), pg_temp.code('A'), pg_temp.ph(3), 'testing.booker@example.invalid');
select pg_temp.check(pg_temp.booked('s16', 't549_b' || pg_temp.tx('sfx'), :'d10', '10:00', '11:00'),
  'S5 another address is answered (booked)');
do $$ declare i int; begin
  for i in 1 .. 9 loop perform pg_temp.q('si' || i, pg_temp.hdr('198.51.100.7'), 'T549NOSUCHCODE' || i, pg_temp.ph(40)); end loop;
  perform pg_temp.q('si10', pg_temp.hdr('198.51.100.7'), pg_temp.code('A'), 'bad phone');
  perform pg_temp.q('si11', pg_temp.hdr('198.51.100.7'), pg_temp.code('A'), pg_temp.ph(41));
end $$;
select pg_temp.check(pg_temp.a('si9') = pg_temp.st('invalid') and pg_temp.a('si11') = pg_temp.st('try_later')
                     and pg_temp.lk(pg_temp.h('198.51.100.7'), null, 'invalid') = 10,
  'S6 invalid lookups within the limit count: ten of them, then try_later');
update public.referral_booking_lookups set created_at = created_at - interval '61 minutes' where sender_key = pg_temp.h('203.0.113.49');
select pg_temp.q('s17', pg_temp.hdr('203.0.113.49'), pg_temp.code('A'), pg_temp.ph(33));
select pg_temp.check(pg_temp.a('s17') = pg_temp.st('none'), 'S7 an hour later the sender is answered again: ' || pg_temp.a('s17')::text);

-- ═════ V senders ═════
do $$ declare i int; begin
  for i in 1 .. 5 loop perform pg_temp.q('v' || i, pg_temp.hdr('2001:db8:1:2::1'), pg_temp.code('A'), pg_temp.ph(50 + i)); end loop;
  for i in 6 .. 10 loop perform pg_temp.q('v' || i, pg_temp.hdr('2001:DB8:1:2:ffff:0:0:9'), pg_temp.code('A'), pg_temp.ph(50 + i)); end loop;
end $$;
select pg_temp.q('v11', pg_temp.hdr('2001:db8:1:2:abcd::77'), pg_temp.code('A'), pg_temp.ph(61));
select pg_temp.q('v12', pg_temp.hdr('2001:db8:1:3::1'), pg_temp.code('A'), pg_temp.ph(61));
select pg_temp.check(pg_temp.lk(pg_temp.h('2001:db8:1:2::/64')) = 11 and pg_temp.a('v11') = pg_temp.st('try_later')
                     and pg_temp.a('v12') = pg_temp.st('none') and pg_temp.lk(pg_temp.h('2001:db8:1:3::/64')) = 1,
  'V1 one IPv6 /64 is one sender (written three ways); another /64 is not');
select pg_temp.q('v13', pg_temp.hdr('::ffff:203.0.113.60'), pg_temp.code('A'), pg_temp.ph(62));
select pg_temp.q('v14', json_build_object('x-forwarded-for', '203.0.113.49')::text, pg_temp.code('A'), pg_temp.ph(63));
select pg_temp.q('v15', pg_temp.hdr('not an address'), pg_temp.code('A'), pg_temp.ph(64));
select pg_temp.check(pg_temp.lk(pg_temp.h('203.0.113.60'), pg_temp.ph(62)) = 1
                     and (select sender_key from public.referral_booking_lookups where phone_key = pg_temp.ph(63)) is null
                     and (select sender_key from public.referral_booking_lookups where phone_key = pg_temp.ph(64)) is null
                     and pg_temp.a('v14') = pg_temp.st('none'),
  'V2 ::ffff:203.0.113.60 is 203.0.113.60; x-forwarded-for alone, or a header that is no address, is no sender');
-- The same key as the sign-up keeps (529), for the same address.
select set_config('request.headers', pg_temp.hdr('192.0.2.77'), true) \g /dev/null
select pg_temp.put('v_signup', (public.affiliate_referral_signup(pg_temp.code('A'), 'Testing', 'Samekey', pg_temp.ph(70), null))::text);
select set_config('request.headers', '', true) \g /dev/null
select pg_temp.q('v16', pg_temp.hdr('192.0.2.77'), pg_temp.code('A'), pg_temp.ph(70));
select pg_temp.check((select e.sender_key from public.referral_signup_events e where e.normalized_phone = pg_temp.ph(70) order by e.created_at desc limit 1)
                     = (select l.sender_key from public.referral_booking_lookups l where l.phone_key = pg_temp.ph(70))
                     and (select l.sender_key from public.referral_booking_lookups l where l.phone_key = pg_temp.ph(70)) = pg_temp.h('192.0.2.77'),
  'V3 the sender key is exactly the one affiliate_referral_signup keeps for the same address: ' || coalesce(pg_temp.tx('v_signup'), 'null'));

-- ═════ P one phone ═════
select pg_temp.bk('t549_p' || pg_temp.tx('sfx'), pg_temp.sgday(:'d5', '18:00'), pg_temp.ph(80), 'testing.phone@example.invalid');
do $$ declare i int; begin
  for i in 1 .. 4 loop
    perform pg_temp.q('p' || i, pg_temp.hdr('192.0.2.' || (10 + i)), pg_temp.code('A'), pg_temp.ph(80), 'guess' || i || '@example.invalid');
  end loop;
  perform pg_temp.q('p5', null, pg_temp.code('A'), pg_temp.ph(80), 'guess5@example.invalid');
end $$;
select pg_temp.q('p6', pg_temp.hdr('192.0.2.30'), pg_temp.code('A'), pg_temp.ph(80), 'testing.phone@example.invalid');
select pg_temp.q('p7', pg_temp.hdr('192.0.2.31'), pg_temp.code('A'), pg_temp.ph(80), 'testing.phone@example.invalid');
select pg_temp.check(pg_temp.a('p4') = pg_temp.st('needs_email') and pg_temp.a('p5') = pg_temp.st('needs_email')
                     and pg_temp.a('p6') = pg_temp.st('try_later') and pg_temp.a('p7') = pg_temp.st('try_later'),
  'P1 five wrong emails on one number (from five senders and none), then try_later, the right email too: ' || pg_temp.a('p6')::text);
select pg_temp.check(pg_temp.lk(null, pg_temp.ph(80), 'try_later') = 1 and pg_temp.lk(null, pg_temp.ph(80)) = 6
                     and pg_temp.lk(pg_temp.h('192.0.2.30'), pg_temp.ph(80), 'try_later') = 1,
  'P2 the phone''s refusal is recorded once an hour, with the phone and the sender');
-- One sender on one number: the phone's limit first (its refusals do not count for the sender).
do $$ declare i int; begin
  for i in 1 .. 10 loop perform pg_temp.q('pq' || i, pg_temp.hdr('192.0.2.40'), pg_temp.code('A'), pg_temp.ph(82)); end loop;
end $$;
select pg_temp.check(pg_temp.a('pq5') = pg_temp.st('none') and pg_temp.a('pq6') = pg_temp.st('try_later') and pg_temp.lk(null, pg_temp.ph(82)) = 6,
  'P3 the phone''s limit holds against one sender too (5 answered, then try_later)');
select pg_temp.check(pg_temp.lk(pg_temp.h('192.0.2.40')) = 6 and pg_temp.lk(pg_temp.h('192.0.2.40'), null, 'try_later') = 1,
  'P3b of them the sender has 5 lookups and the one refusal (try_later is not counted)');
-- A sender's refusal is not a lookup of the phone: 192.0.2.41 fills its 10 on two other numbers, then asks about ph(81).
do $$ declare i int; begin
  for i in 1 .. 10 loop perform pg_temp.q('ps' || i, pg_temp.hdr('192.0.2.41'), pg_temp.code('A'), pg_temp.ph(83 + i % 2)); end loop;
end $$;
select pg_temp.bk('t549_q' || pg_temp.tx('sfx'), pg_temp.sgday(:'d5', '19:00'), pg_temp.ph(81), 'testing.q@example.invalid');
select pg_temp.q('pr1', pg_temp.hdr('192.0.2.41'), pg_temp.code('A'), pg_temp.ph(81), 'testing.q@example.invalid');
select pg_temp.q('pr2', pg_temp.hdr('192.0.2.41'), pg_temp.code('A'), pg_temp.ph(81), 'testing.q@example.invalid');
select pg_temp.check(pg_temp.a('ps10') = pg_temp.st('none') and pg_temp.a('pr1') = pg_temp.st('try_later') and pg_temp.a('pr2') = pg_temp.st('try_later')
                     and pg_temp.lk(null, pg_temp.ph(81)) = 0,
  'P4 a sender''s refusal records nothing on the phone (the sender''s refusal row has no phone)');
update public.referral_booking_lookups set created_at = created_at - interval '61 minutes' where phone_key = pg_temp.ph(80);
select pg_temp.q('p8', pg_temp.hdr('192.0.2.32'), pg_temp.code('A'), pg_temp.ph(80), 'testing.phone@example.invalid');
select pg_temp.check(pg_temp.booked('p8', 't549_p' || pg_temp.tx('sfx'), :'d5', '18:00', '19:00'),
  'P5 an hour later the number is answered again (booked): ' || pg_temp.a('p8')::text);

-- ═════ L the locks ═════
select pg_temp.check(exists (select 1 from pg_locks l where l.locktype = 'advisory' and l.pid = pg_backend_pid() and l.objsubid = 1
                               and ((l.classid::bigint << 32) | l.objid::bigint) = hashtextextended('referral-booking-sender:' || pg_temp.h('192.0.2.32'), 0))
                     and exists (select 1 from pg_locks l where l.locktype = 'advisory' and l.pid = pg_backend_pid() and l.objsubid = 1
                               and ((l.classid::bigint << 32) | l.objid::bigint) = hashtextextended('referral-booking-phone:' || pg_temp.ph(80), 0)),
  'L1 the sender''s and the phone''s advisory locks are held to the end of the transaction');

-- ═════ R rights ═════
select pg_temp.q('r1', null, pg_temp.code('A'), pg_temp.ph(3), 'testing.booker@example.invalid', 'authenticated');
select pg_temp.q('r2', null, pg_temp.code('A'), pg_temp.ph(4), null, 'authenticated');
select pg_temp.check(pg_temp.booked('r1', 't549_b' || pg_temp.tx('sfx'), :'d10', '10:00', '11:00') and pg_temp.a('r2') = pg_temp.st('needs_email'),
  'R1 a signed-in login gets the same answers');
select pg_temp.check(has_function_privilege('anon', 'public.referral_booking_lookup(text,text,text)', 'execute')
                     and has_function_privilege('authenticated', 'public.referral_booking_lookup(text,text,text)', 'execute')
                     and has_function_privilege('service_role', 'public.referral_booking_lookup(text,text,text)', 'execute')
                     and (select string_agg(x::text, ',' order by x::text) from pg_proc p, unnest(p.proacl) x
                           where p.oid = 'public.referral_booking_lookup(text,text,text)'::regprocedure)
                         = (select string_agg(x::text, ',' order by x::text) from pg_proc p, unnest(p.proacl) x
                             where p.oid = 'public.public_affiliate_referral_info(text)'::regprocedure)
                     and not exists (select 1 from pg_proc p, aclexplode(p.proacl) e
                                      where p.oid = 'public.referral_booking_lookup(text,text,text)'::regprocedure and e.grantee = 0),
  'R2 anon, authenticated and the service role may call it, as public_affiliate_referral_info; PUBLIC not');
select pg_temp.check(not has_table_privilege(g, 'public.referral_booking_lookups', p), 'R3 ' || g || ' has no ' || p || ' on referral_booking_lookups')
  from unnest(array['anon', 'authenticated', 'service_role']) g,
       unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER']) p;
select pg_temp.check(not has_sequence_privilege(g, 'public.referral_booking_lookups_id_seq', 'usage,select,update')
                     and not has_any_column_privilege(g, 'public.referral_booking_lookups', 'select,insert,update,references'),
  'R4 ' || g || ' has nothing on the id sequence and no column grant')
  from unnest(array['anon', 'authenticated', 'service_role']) g;
create function pg_temp.as_role(p_role text, q text) returns text language plpgsql as $f$
declare s text;
begin
  begin
    perform set_config('request.jwt.claims', json_build_object('role', p_role)::text, true);
    execute format('set local role %I', p_role);
    execute q;
    raise exception using errcode = 'P0999', message = 'ok';
  exception
    when sqlstate 'P0999' then return 'ok';
    when others then get stacked diagnostics s = returned_sqlstate; return 'ERR ' || s;
  end;
end $f$;
select pg_temp.check(pg_temp.as_role(g, 'select count(*) from public.referral_booking_lookups') = 'ERR 42501'
                     and pg_temp.as_role(g, 'insert into public.referral_booking_lookups(outcome) values (''none'')') = 'ERR 42501'
                     and pg_temp.as_role(g, 'truncate public.referral_booking_lookups') = 'ERR 42501',
  'R5 ' || g || ' is refused reading, writing and emptying the table (42501)')
  from unnest(array['anon', 'authenticated']) g;
select pg_temp.check(p.prosecdef and pg_get_userbyid(p.proowner) = 'postgres' and p.proconfig = array['search_path=public, pg_temp']
                     and md5(pg_get_functiondef(p.oid)) = '8385a3401954768048e293fb0fac7dbf' and p.provolatile = 'v',
  'R6 owner postgres, SECURITY DEFINER, search_path public, pg_temp, 549''s AFTER md5: ' || md5(pg_get_functiondef(p.oid)))
  from pg_proc p where p.oid = 'public.referral_booking_lookup(text,text,text)'::regprocedure;
select pg_temp.check(c.relrowsecurity and not exists (select 1 from pg_policy p where p.polrelid = c.oid)
                     and pg_get_userbyid(c.relowner) = 'postgres' and c.relacl::text = '{postgres=arwdDxtm/postgres}',
  'R7 the table: row level security on, no policy, the owner''s alone')
  from pg_class c where c.oid = 'public.referral_booking_lookups'::regclass;
savepoint r8;
\set ON_ERROR_STOP off
insert into public.referral_booking_lookups(sender_key, outcome) values ('203.0.113.49', 'none');
\set ON_ERROR_STOP on
rollback to savepoint r8;
select :'LAST_ERROR_MESSAGE' as r8a \gset
\set ON_ERROR_STOP off
insert into public.referral_booking_lookups(outcome) values ('registered');
\set ON_ERROR_STOP on
rollback to savepoint r8;
select pg_temp.check(:'r8a' like '%referral_booking_lookups_sender_key_is_a_hash%' and :'LAST_ERROR_MESSAGE' like '%referral_booking_lookups_outcome_check%',
  'R8 the table refuses a sender key that is not a hash, and an outcome that is not one of the five');
select pg_temp.check(not exists (select 1 from public.referral_booking_lookups l
                                  where l.sender_key is not null and l.sender_key in (encode(sha256(convert_to('203.0.113.49', 'UTF8')), 'hex'),
                                                                                       encode(sha256(convert_to('192.0.2.77', 'UTF8')), 'hex')))
                     and (select md5(salt) from public.referral_sender_salt) = (select m from salt0)
                     and (select count(*) from public.referral_sender_salt) = 1,
  'R9 no key is an unsalted hash of an address; 529''s salt is unchanged');
\if :by_us
select pg_temp.check(pg_temp.fp() = 'da952c4a3e002f6fc20da3260b1cff95/1471', 'R10 the function fingerprint after 549: ' || pg_temp.fp());

-- ═════ U the undo, and M ═════
savepoint u0;
create or replace function public.referral_booking_lookup(p_code text, p_phone text, p_email text default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $f$ begin return '{"state":"none"}'; end $f$;
\set ON_ERROR_STOP off
\ir ../undo-549.sql
\set ON_ERROR_STOP on
rollback to savepoint u0;
select pg_temp.check(:'LAST_ERROR_MESSAGE' like 'undo 549: public.referral_booking_lookup(text,text,text) is not 549''s%',
  'U0 the undo refuses when the function is not 549''s: ' || :'LAST_ERROR_MESSAGE');
savepoint u1;
\ir ../undo-549.sql
select pg_temp.check(to_regprocedure('public.referral_booking_lookup(text,text,text)') is null
                     and to_regclass('public.referral_booking_lookups') is null and to_regclass('public.referral_booking_lookups_id_seq') is null
                     and pg_temp.fp() = (select f from fp0),
  'U1 the undo drops the function and the table, and the fingerprint is as before 549: ' || pg_temp.fp());
savepoint u2;
\set ON_ERROR_STOP off
\ir ../undo-549.sql
\set ON_ERROR_STOP on
rollback to savepoint u2;
select pg_temp.check(:'LAST_ERROR_MESSAGE' like 'undo 549: 549 is not in on this database%', 'U2 a second undo refuses: ' || :'LAST_ERROR_MESSAGE');
\ir ../../../supabase/549_referral_page_shows_an_existing_booking.sql
select pg_temp.check(pg_temp.fp() = 'da952c4a3e002f6fc20da3260b1cff95/1471'
                     and (select count(*) from public.referral_booking_lookups) = 0,
  'U3 549 after the undo makes the same again (an empty table)');
rollback to savepoint u1;
savepoint m1;
\set ON_ERROR_STOP off
\ir ../../../supabase/549_referral_page_shows_an_existing_booking.sql
\set ON_ERROR_STOP on
rollback to savepoint m1;
select pg_temp.check(:'LAST_ERROR_MESSAGE' like '549 is already in on this database%', 'M1 549 a second time refuses: ' || :'LAST_ERROR_MESSAGE');
\else
\echo NOTE  B0, B1, R10, U and M are skipped (549 was not installed by this file)
\endif

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, E'\n' order by n) from failed); end if;
  raise notice 'All 549 checks passed.';
end $$;
rollback;
