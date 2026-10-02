-- Free guests in the website's sync (382, on 380).
--
--   G1  An event with no free guests: "free" is [] (and too_soon and refused
--       still carry nothing else).
--   G2  Every free guest of the channel's event, cancelled ones too, oldest
--       first (created_at, then id), each with exactly order_id, name, phone,
--       email, days, status, registered_by, notes and date: the phone is the
--       guest's (a blank one is none), else their customer's; the email their
--       customer's (a blank one is none), else none; the days in order; the
--       staff member's name; the notes (blank are none); the day they were
--       added, in Singapore.
--   G3  Later syncs: a cancelled guest says so and a restored one is
--       registered again, changed days and notes come through, and every key
--       stays as it was while guests are added after.
--   G4  The key: FREE- and the first 8 hex digits of the id, in capitals. A
--       later free guest of the event with the same 8 takes 12 (later by
--       created_at, then by id); a free guest of another event with the same
--       8 changes nothing. Every key is unique.
--   G5  Only free guests: the people of a counter sale or a staff-link order
--       of the event, and other events' free guests, are not in "free".
--   G6  Everything else is 380's: the function is 380's text with the free
--       guests added, and its answer without "free" is what 380's gives for
--       the same data; 382 goes on again over 380 run again.
--   G7  382 refuses a web_order_sync that is neither 380's nor its own, and a
--       database without one, leaving it as it was; run again it changes
--       nothing (the same md5, the one its header records, and the same
--       answer); only the service role may call the sync.
--
-- Run from the repository's root (it reads 382 to apply it as one unit, as
-- the migration tool does), after 380 and 382: begin; 373, 376, 380, 382,
-- then this, all rolled back (as the 2 Oct 2026 checks did).
--
-- Every check runs, then the file fails if any did. Disposable database only;
-- everything is rolled back. Fixtures carry a random suffix; phones are made
-- up (+65 9382 ....), names and emails are fixtures.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '10s';
set local statement_timeout = '120s';
-- Production's user_has_store_access (29 Sep 2026).
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
-- The error a statement (or a whole file) raises, or null when it succeeds.
-- Inside the exception block a failure leaves nothing behind, as a migration
-- applied in one transaction.
create function pg_temp.err(q text) returns text language plpgsql as
$$begin execute q; return null; exception when others then return sqlerrm; end$$;
create function pg_temp.d(n int) returns date language sql as $$ select public.sg_today() + n $$;
-- A made-up phone no customer, order or earlier pick has.
create function pg_temp.phone() returns text language sql volatile as $$
  select '+659382' || lpad(n::text, 4, '0') from generate_series(0, 9999) n
   where not exists (select 1 from public.customers c
                      where regexp_replace(coalesce(c.phone, ''), '\D', '', 'g') = '659382' || lpad(n::text, 4, '0'))
     and not exists (select 1 from public.web_orders w
                      where regexp_replace(coalesce(w.buyer_phone, ''), '\D', '', 'g') = '659382' || lpad(n::text, 4, '0'))
     and not exists (select 1 from tx where regexp_replace(tx.v, '\D', '', 'g') = '659382' || lpad(n::text, 4, '0'))
   order by random() limit 1
$$;
create function pg_temp.customer(key text, email text) returns uuid language plpgsql as
$$declare c uuid; begin
  insert into tx values ('ph_' || key, pg_temp.phone());
  insert into public.customers(full_name, phone, email)
  values ('F382 Customer ' || key || ' ' || pg_temp.tx('sfx'), pg_temp.tx('ph_' || key), email) returning id into c;
  insert into fx values (key, c);
  return c;
end$$;
-- A free guest added on the Guests tab (as the current user), then dated.
create function pg_temp.add_guest(key text, gname text, phone text, cust uuid, days date[], by_key text,
  notes text, created timestamptz, ev text default 'ev') returns uuid language plpgsql as
$$declare g uuid; begin
  g := (public.event_save_guest(jsonb_build_object('event_id', pg_temp.fx(ev), 'name', gname, 'phone', phone,
          'customer_id', cust, 'days', to_jsonb(days), 'registered_by', pg_temp.fx(by_key), 'notes', notes))->>'guest_id')::uuid;
  update public.event_guests set created_at = created where id = g;
  insert into fx values (key, g);
  return g;
end$$;
-- A free guest with a chosen id: its first 8 hex digits and zeros after.
create function pg_temp.add_guest_like(key text, gname text, like_key text, created timestamptz, ev text default 'ev')
returns uuid language plpgsql as
$$declare g uuid := (left(replace(pg_temp.fx(like_key)::text, '-', ''), 8) || '-0000-0000-0000-000000000000')::uuid; begin
  insert into public.event_guests (id, event_id, name, source, registered_by, created_at)
  values (g, pg_temp.fx(ev), gname, 'free', pg_temp.fx('owner'), created);
  insert into public.event_guest_days (guest_id, day)
  select g, d.day from public.event_days d where d.event_id = pg_temp.fx(ev) order by d.day limit 1;
  insert into fx values (key, g);
  return g;
end$$;
-- The key a guest's id gives with n hex digits.
create function pg_temp.key(key text, n int) returns text language sql as
$$ select 'FREE-' || upper(left(replace(pg_temp.fx(key)::text, '-', ''), n)) $$;
-- A sync now, as the service role, however soon after the last.
create function pg_temp.sync_now() returns jsonb language plpgsql as
$$begin
  update public.web_order_channels set last_sync_at = null where key = pg_temp.tx('channel');
  perform set_config('request.jwt.claim.sub', '', true);
  return public.web_order_sync(pg_temp.tx('channel'));
end$$;
-- The free guest a sync kept as tx(sync) lists with that name.
create function pg_temp.free(sync text, gname text) returns jsonb language sql as
$$ select x from jsonb_array_elements(pg_temp.tx(sync)::jsonb->'free') x where x->>'name' = gname $$;
create function pg_temp.names(sync text) returns text[] language sql as
$$ select coalesce(array_agg(x->>'name' order by k), '{}') from jsonb_array_elements(pg_temp.tx(sync)::jsonb->'free') with ordinality t(x, k) $$;
create function pg_temp.sync_md5() returns text language sql as
$$ select md5(prosrc) from pg_proc where oid = to_regprocedure('public.web_order_sync(text)') $$;
create function pg_temp.touch(fn regprocedure) returns void language plpgsql as
$$begin execute regexp_replace(pg_get_functiondef(fn), '\$function\$\s*$', E'-- changed\n$function$'); end$$;
-- 382 as the migration tool applies it, and the md5 its header records.
\set m382 `cat supabase/382_free_guests_in_the_sync.sql`
insert into tx values ('m382', :'m382');
create function pg_temp.m382() returns text language sql as $$ select pg_temp.tx('m382') $$;
create function pg_temp.recorded_md5() returns text language sql as
$$ select (regexp_match(pg_temp.m382(), '--   web_order_sync\(text\)\s+([0-9a-f]{32})'))[1] $$;

-- ═════ Fixtures ═════
do $$
declare sfx text := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  u uuid; k text; st uuid; ev uuid; ev2 uuid; o1 uuid;
begin
  insert into tx values ('sfx', sfx), ('channel', 'f382-' || lower(sfx));
  foreach k in array array['owner','staff','seller'] loop
    u := gen_random_uuid();
    insert into auth.users(id, email) values (u, 'f382-' || k || '-' || lower(sfx) || '@tests.invalid');
    insert into profiles(id, full_name, email, role, is_active)
    values (u, 'F382 ' || initcap(k) || ' ' || sfx, 'f382-' || k || '-' || lower(sfx) || '@tests.invalid',
            case k when 'owner' then 'owner' else 'staff' end::user_role, true);
    insert into fx values (k, u);
  end loop;
  perform pg_temp.as_user('owner');
  insert into stores(name, code, country_code) values ('F382 Van ' || sfx, 'F382V' || sfx, 'SG') returning id into st;
  insert into fx values ('van', st);
  ev := public.event_save(jsonb_build_object('name', 'F382 Birthday ' || sfx,
    'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(7)), jsonb_build_object('day', pg_temp.d(8))),
    'store_ids', jsonb_build_array(st),
    'options', jsonb_build_array(jsonb_build_object('name', '1 Day', 'days_count', 1, 'price', 10))));
  select id into o1 from public.event_ticket_options where event_id = ev;
  ev2 := public.event_save(jsonb_build_object('name', 'F382 Other ' || sfx,
    'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(9))), 'store_ids', jsonb_build_array(st),
    'options', jsonb_build_array(jsonb_build_object('name', 'Entry', 'days_count', 1, 'price', 10))));
  insert into fx values ('ev', ev), ('one', o1), ('ev2', ev2);
  insert into public.payment_methods(name, is_active) values ('F382 Online ' || sfx, true) returning id into u;
  insert into public.web_order_channels (key, event_id, ticket_map, store_id, acting_profile_id, payment_method_id, mode)
  values (pg_temp.tx('channel'), ev,
          jsonb_build_object('day1', jsonb_build_object('option_id', o1, 'days', jsonb_build_array(pg_temp.d(7)))),
          st, pg_temp.fx('owner'), u, 'live');
end $$;

-- ═════ G1 No free guests yet ═════
do $$ begin
  insert into tx values ('s0', pg_temp.sync_now()::text);
  insert into tx values ('s0_soon', public.web_order_sync(pg_temp.tx('channel'))::text);
  insert into tx values ('s0_unknown', public.web_order_sync('no-such-channel-' || pg_temp.tx('sfx'))::text);
end $$;
select pg_temp.check((select array_agg(k order by k) from jsonb_object_keys(pg_temp.tx('s0')::jsonb) k)
                       = array['counter','event','free','orders','status']
    and pg_temp.tx('s0')::jsonb->'free' = '[]'::jsonb,
  'G1 an ok sync carries "free", an empty list while the event has no free guests');
select pg_temp.check(pg_temp.tx('s0_soon')::jsonb = jsonb_build_object('status', 'too_soon')
    and pg_temp.tx('s0_unknown')::jsonb = jsonb_build_object('status', 'refused'),
  'G1 too_soon and refused still carry nothing else');

-- ═════ G2 The free guests ═════
-- Ben is added first (23:59:59 in Singapore), Ann and Cal together at 00:30
-- the next day, then Dee and Eve (cancelled). A counter sale and a
-- staff-link order of the event, and a free guest of another event, too.
select pg_temp.as_user('owner');
do $$ begin
  perform pg_temp.add_guest('ann', 'Free Ann', pg_temp.phone(), pg_temp.customer('cust_a', 'free-ann@tests.invalid'),
            array[pg_temp.d(8), pg_temp.d(7)], 'seller', 'VEG', '2026-09-30 16:30:00+00');
  perform pg_temp.add_guest('ben', 'Free Ben', null, pg_temp.customer('cust_b', '  '),
            array[pg_temp.d(7)], 'staff', null, '2026-09-30 15:59:59+00');
  perform pg_temp.add_guest('cal', 'Free Cal', null, null, array[pg_temp.d(8)], 'staff', null, '2026-09-30 16:30:00+00');
  -- Who registered Cal is no longer known, and Cal's notes are blank.
  update public.event_guests set registered_by = null, notes = '  ' where id = pg_temp.fx('cal');
  perform pg_temp.add_guest('dee', 'Free Dee', null, pg_temp.customer('cust_d', null),
            array[pg_temp.d(7), pg_temp.d(8)], 'owner', null, '2026-10-01 01:00:00+00');
  -- Dee's own phone is blank.
  update public.event_guests set phone = '   ' where id = pg_temp.fx('dee');
  insert into tx values ('ph_eve', pg_temp.phone());
  perform pg_temp.add_guest('eve', 'Free Eve', pg_temp.tx('ph_eve'), null, array[pg_temp.d(7)], 'seller', 'Plus one',
            '2026-10-01 02:00:00+00');
  perform public.event_set_guest_cancelled(pg_temp.fx('eve'), true, 'F382 not coming');
  perform pg_temp.add_guest('other', 'Free Other', null, null, array[pg_temp.d(9)], 'staff', null,
            '2026-09-01 00:00:00+00', 'ev2');
  -- A counter sale of two, and a staff-link order of one.
  perform public.create_invoice_with_details(pg_temp.fx('van'), pg_temp.customer('cust_t', 'free-ticket@tests.invalid'), jsonb_build_array(
    jsonb_build_object('kind', 'event_ticket', 'event_ticket_option_id', pg_temp.fx('one'), 'quantity', 2,
      'event_days', jsonb_build_array(pg_temp.d(7)),
      'attendees', jsonb_build_array(jsonb_build_object('name', 'Ticket One'), jsonb_build_object('name', 'Ticket Two')))),
    jsonb_build_object('business_date', pg_temp.d(0)::text));
  perform set_config('request.jwt.claim.sub', '', true);
  insert into tx values ('door', public.web_order_door(jsonb_build_object('channel', pg_temp.tx('channel'), 'provider', 'door',
    'order_id', 'OFF-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || pg_temp.tx('sfx'),
    'ticket', 'day1', 'quantity', 1, 'amount_total_cents', 1000, 'paid_on', pg_temp.d(0)::text, 'method', 'cash',
    'registered_at', now(), 'buyer', jsonb_build_object('first_name', 'Door', 'last_name', 'Buyer', 'whatsapp', pg_temp.phone()),
    'attendees', jsonb_build_array(jsonb_build_object('name', 'Door Person'))))->>'status');
  insert into tx values ('s1', pg_temp.sync_now()::text);
end $$;
select pg_temp.check(pg_temp.names('s1') = case when pg_temp.fx('ann') < pg_temp.fx('cal')
                                               then array['Free Ben', 'Free Ann', 'Free Cal', 'Free Dee', 'Free Eve']
                                               else array['Free Ben', 'Free Cal', 'Free Ann', 'Free Dee', 'Free Eve'] end,
  'G2 every free guest of the event, cancelled ones too, oldest first; added together, by id');
select pg_temp.check((select bool_and((select array_agg(k order by k) from jsonb_object_keys(x) k)
                                       = array['date','days','email','name','notes','order_id','phone','registered_by','status'])
                        from jsonb_array_elements(pg_temp.tx('s1')::jsonb->'free') x),
  'G2 each comes with exactly order_id, name, phone, email, days, status, registered_by, notes and date');
select pg_temp.check(pg_temp.free('s1', 'Free Ann') = jsonb_build_object('order_id', pg_temp.key('ann', 8), 'name', 'Free Ann',
                       'phone', (select phone from public.event_guests where id = pg_temp.fx('ann')),
                       'email', 'free-ann@tests.invalid', 'days', jsonb_build_array(pg_temp.d(7)::text, pg_temp.d(8)::text),
                       'status', 'registered', 'registered_by', 'F382 Seller ' || pg_temp.tx('sfx'), 'notes', 'VEG',
                       'date', '2026-10-01'),
  'G2 a guest with a phone and a customer: their own phone, the customer''s email, the days in order, who registered them, notes, and the day added in Singapore');
select pg_temp.check(pg_temp.free('s1', 'Free Ben') = jsonb_build_object('order_id', pg_temp.key('ben', 8), 'name', 'Free Ben',
                       'phone', (select phone from public.customers where id = pg_temp.fx('cust_b')), 'email', null, 'days', jsonb_build_array(pg_temp.d(7)::text),
                       'status', 'registered', 'registered_by', 'F382 Staff ' || pg_temp.tx('sfx'), 'notes', null,
                       'date', '2026-09-30'),
  'G2 a guest with no phone has their customer''s; a blank customer email is none; 23:59:59 in Singapore is that day');
select pg_temp.check(pg_temp.free('s1', 'Free Cal') = jsonb_build_object('order_id', pg_temp.key('cal', 8), 'name', 'Free Cal',
                       'phone', null, 'email', null, 'days', jsonb_build_array(pg_temp.d(8)::text),
                       'status', 'registered', 'registered_by', null, 'notes', null, 'date', '2026-10-01'),
  'G2 a guest with no phone and no customer has neither; no one known as Registered by; blank notes are none');
select pg_temp.check(pg_temp.free('s1', 'Free Dee') = jsonb_build_object('order_id', pg_temp.key('dee', 8), 'name', 'Free Dee',
                       'phone', (select phone from public.customers where id = pg_temp.fx('cust_d')), 'email', null,
                       'days', jsonb_build_array(pg_temp.d(7)::text, pg_temp.d(8)::text),
                       'status', 'registered', 'registered_by', 'F382 Owner ' || pg_temp.tx('sfx'), 'notes', null,
                       'date', '2026-10-01'),
  'G2 a blank phone of their own gives the customer''s; a customer with no email gives none');
select pg_temp.check(pg_temp.free('s1', 'Free Eve') = jsonb_build_object('order_id', pg_temp.key('eve', 8), 'name', 'Free Eve',
                       'phone', pg_temp.tx('ph_eve'), 'email', null, 'days', jsonb_build_array(pg_temp.d(7)::text),
                       'status', 'cancelled', 'registered_by', 'F382 Seller ' || pg_temp.tx('sfx'), 'notes', 'Plus one',
                       'date', '2026-10-01'),
  'G2 a cancelled guest is listed, as cancelled');

-- ═════ G5 Only free guests ═════
select pg_temp.check(pg_temp.tx('door') = 'recorded'
    and jsonb_array_length(pg_temp.tx('s1')::jsonb->'counter') = 1
    and (select array_agg(p->>'name' order by (p->>'position')::int)
           from jsonb_array_elements(pg_temp.tx('s1')::jsonb->'counter'->0->'people') p) = array['Ticket One', 'Ticket Two']
    and (select x->'people'->0->>'name' from jsonb_array_elements(pg_temp.tx('s1')::jsonb->'orders') x) = 'Door Person'
    and cardinality(pg_temp.names('s1')) = (select count(*) from public.event_guests
                                             where event_id = pg_temp.fx('ev') and source = 'free')
    and (select count(*) from public.event_guests where event_id = pg_temp.fx('ev') and source = 'ticket') = 2
    and not exists (select 1 from unnest(pg_temp.names('s1')) n where n in ('Ticket One', 'Ticket Two', 'Door Person', 'Free Other')),
  'G5 the people of a counter sale and of a staff-link order stay in counter and orders, and another event''s free guest is not this one''s');

-- ═════ G3 Later syncs ═════
select pg_temp.as_user('owner');
do $$ begin
  perform public.event_set_guest_cancelled(pg_temp.fx('ann'), true, 'F382 changed plans');
  perform public.event_set_guest_cancelled(pg_temp.fx('eve'), false);
  perform public.event_save_guest(jsonb_build_object('id', pg_temp.fx('cal'), 'name', 'Free Cal',
            'days', jsonb_build_array(pg_temp.d(8), pg_temp.d(7)), 'notes', 'Wheelchair'));
  -- ═════ G4 (set up) ═════
  -- Gus: added later, with Ann's 8 hex digits and an id that sorts before
  -- Ann's. Fay and Ivy: added together, with the same 8; Ivy's id sorts
  -- first. Hal: another event's, with Ben's 8, added before Ben.
  perform pg_temp.add_guest_like('gus', 'Free Gus', 'ann', '2026-10-01 04:00:00+00');
  perform pg_temp.add_guest('fay', 'Free Fay', null, null, array[pg_temp.d(7)], 'staff', null, '2026-10-01 05:00:00+00');
  perform pg_temp.add_guest_like('ivy', 'Free Ivy', 'fay', '2026-10-01 05:00:00+00');
  perform pg_temp.add_guest_like('hal', 'Free Hal', 'ben', '2026-09-01 00:00:00+00', 'ev2');
  insert into tx values ('s2', pg_temp.sync_now()::text);
end $$;
select pg_temp.check((pg_temp.free('s2', 'Free Ann')->>'status', pg_temp.free('s2', 'Free Eve')->>'status')
                       = ('cancelled', 'registered')
    and pg_temp.free('s2', 'Free Ann') - 'status' = pg_temp.free('s1', 'Free Ann') - 'status'
    and pg_temp.free('s2', 'Free Eve') - 'status' = pg_temp.free('s1', 'Free Eve') - 'status',
  'G3 a guest cancelled since says cancelled, a restored one registered, and nothing else about them changes');
select pg_temp.check((pg_temp.free('s2', 'Free Cal')->'days', pg_temp.free('s2', 'Free Cal')->>'notes')
                       = (jsonb_build_array(pg_temp.d(7)::text, pg_temp.d(8)::text), 'Wheelchair'),
  'G3 changed days and notes come through');
select pg_temp.check((select bool_and(pg_temp.free('s2', n)->>'order_id' = pg_temp.free('s1', n)->>'order_id')
                        from unnest(pg_temp.names('s1')) n)
    and (pg_temp.names('s2'))[1:5] = pg_temp.names('s1')
    and (pg_temp.names('s2'))[6:] = array['Free Gus', 'Free Ivy', 'Free Fay'],
  'G3 every guest keeps their key while guests are added after them, who come last');

-- ═════ G4 The key ═════
select pg_temp.check(pg_temp.free('s2', 'Free Gus')->>'order_id' = pg_temp.key('gus', 12)
    and pg_temp.free('s2', 'Free Gus')->>'order_id' = pg_temp.key('ann', 8) || '0000'
    and pg_temp.free('s2', 'Free Ann')->>'order_id' = pg_temp.key('ann', 8),
  'G4 a later guest with an earlier guest''s 8 hex digits takes 12 (later by when they were added, though their id sorts first)');
select pg_temp.check(pg_temp.free('s2', 'Free Ivy')->>'order_id' = pg_temp.key('ivy', 8)
    and pg_temp.free('s2', 'Free Fay')->>'order_id' = pg_temp.key('fay', 12),
  'G4 of two added together with the same 8, the one whose id sorts first keeps 8');
select pg_temp.check(pg_temp.free('s2', 'Free Ben')->>'order_id' = pg_temp.key('ben', 8)
    and pg_temp.free('s2', 'Free Hal') is null,
  'G4 another event''s free guest with the same 8 changes nothing (and is not listed)');
select pg_temp.check((select bool_and(x->>'order_id' ~ '^FREE-[0-9A-F]{8}([0-9A-F]{4})?$')
                             and count(distinct x->>'order_id') = count(*) and count(*) = 8
                        from jsonb_array_elements(pg_temp.tx('s2')::jsonb->'free') x)
    and pg_temp.key('ann', 8) = 'FREE-' || upper(substr(pg_temp.fx('ann')::text, 1, 8)),
  'G4 every key is FREE- and 8 (or 12) capital hex digits of the id, and no two are the same');

-- ═════ G6 Everything else is 380's ═════
-- The function without its free guests is 380's, character for character.
select pg_temp.check((select md5(left(p, strpos(p, E',\n    -- 382: every free guest') - 1)
                                 || substr(p, strpos(p, $q$g.source = 'free') f), '[]'::jsonb)$q$)
                                              + length($q$g.source = 'free') f), '[]'::jsonb)$q$)))
                        from (select prosrc as p from pg_proc where oid = 'public.web_order_sync(text)'::regprocedure) s)
                       = '8ef0796822369dbceac26c16556506a7',
  'G6 web_order_sync is 380''s text with the free guests added, and nothing else changed');
do $$ begin insert into tx values ('s382', pg_temp.sync_now()::text); end $$;
-- 380 again (it puts back its own web_order_sync), then 382 again over it.
\ir ../../../supabase/380_seminar_staff_link_orders.sql
do $$ begin
  insert into tx values ('md5_380', pg_temp.sync_md5()), ('s380', pg_temp.sync_now()::text);
  insert into tx values ('again_380', coalesce(pg_temp.err(pg_temp.m382()), 'applied'));
  insert into tx values ('s382_again', pg_temp.sync_now()::text);
end $$;
select pg_temp.check(pg_temp.tx('md5_380') = '8ef0796822369dbceac26c16556506a7'
    and not (pg_temp.tx('s380')::jsonb ? 'free')
    and pg_temp.tx('s382')::jsonb - 'free' = pg_temp.tx('s380')::jsonb
    and jsonb_array_length(pg_temp.tx('s380')::jsonb->'orders') = 1 and jsonb_array_length(pg_temp.tx('s380')::jsonb->'counter') = 1,
  'G6 the answer without "free" is what 380''s sync gives for the same orders and counter sales');
select pg_temp.check(pg_temp.tx('again_380') = 'applied' and pg_temp.sync_md5() = pg_temp.recorded_md5()
    and pg_temp.tx('s382_again')::jsonb = pg_temp.tx('s382')::jsonb,
  'G6 382 goes on over 380''s web_order_sync, and answers as before');

-- ═════ G7 The guard, a second run, and who may call it ═════
savepoint g7;
select pg_temp.touch('public.web_order_sync(text)');
select coalesce(pg_temp.err(pg_temp.m382()), 'applied') as g7_changed_err,
       (select prosrc ~ '-- changed' from pg_proc where oid = 'public.web_order_sync(text)'::regprocedure) as g7_changed_kept \gset
rollback to savepoint g7;
drop function public.web_order_sync(text);
select coalesce(pg_temp.err(pg_temp.m382()), 'applied') as g7_missing_err,
       to_regprocedure('public.web_order_sync(text)') is null as g7_missing_kept \gset
rollback to savepoint g7;
release savepoint g7;
select pg_temp.check(:'g7_changed_err' = '382: public.web_order_sync(text) is not the version this was tested against'
    and :'g7_changed_kept'::boolean,
  'G7 382 refuses a web_order_sync that is neither 380''s nor its own, and leaves it as it was');
select pg_temp.check(:'g7_missing_err' = '382: apply 380 (staff-link orders) first' and :'g7_missing_kept'::boolean,
  'G7 382 refuses a database without web_order_sync (380 first), creating nothing');
do $$ begin
  insert into tx values ('acl_before', (select proacl::text from pg_proc where oid = 'public.web_order_sync(text)'::regprocedure));
  insert into tx values ('rerun', coalesce(pg_temp.err(pg_temp.m382()), 'applied'));
  insert into tx values ('s_rerun', pg_temp.sync_now()::text);
end $$;
select pg_temp.check(pg_temp.tx('rerun') = 'applied' and pg_temp.sync_md5() = pg_temp.recorded_md5()
    and pg_temp.recorded_md5() is not null
    and (select proacl::text from pg_proc where oid = 'public.web_order_sync(text)'::regprocedure) = pg_temp.tx('acl_before')
    and pg_temp.tx('s_rerun')::jsonb = pg_temp.tx('s382')::jsonb,
  'G7 run again, 382 changes nothing: the md5 its header records, the same grants, the same answer');
select pg_temp.check(has_function_privilege('service_role', 'public.web_order_sync(text)', 'execute')
    and not has_function_privilege('authenticated', 'public.web_order_sync(text)', 'execute')
    and not has_function_privilege('anon', 'public.web_order_sync(text)', 'execute')
    and (select p.proacl is not null and not exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0)
           from pg_proc p where p.oid = 'public.web_order_sync(text)'::regprocedure),
  'G7 only the service role may call the sync (not anon, not signed-in staff, not PUBLIC)');

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All free guest sync checks passed.';
end $$;
rollback;
