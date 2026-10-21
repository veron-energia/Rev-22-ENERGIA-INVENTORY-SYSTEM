-- The event website: registrations, VIP and the Website tab (436).
--
-- The owner's requirements, 20 Oct 2026 (Free Two Day Health Seminar):
-- everyone registers free; VIP is S$72 per person, covers both days, and can
-- be bought while registering or later; each VIP gets a S$72 offset voucher
-- and a 3-in-1 voucher on their own account when the payment succeeds, and
-- socks or gloves at the door; every registration matches or makes a
-- customer (433's rules) and is on the guest list; a link with a referral
-- code makes new people the affiliate's referrals (392/425, Q19 = A), who
-- earn commission only on VIP; HitPay is invoiced at once, PayNow and bank
-- transfers wait for a Manager; the Owner makes a key shown once and kept
-- only hashed; never a capacity to customers.
--
--   S  Settings and keys: who saves what, what refuses a save and what only
--      refuses switching on, the venue, a key made in the database and shown
--      once (only its SHA-256 kept), revoked, unknown and wrong-event keys,
--      the request id (replay, conflict), the rate limit (sign-ups that use
--      up theirs never block HitPay's payment notices).
--   I  event_info: title, days, hours, venue (null until set), VIP price; never
--      a capacity or a count; closed when Off, off sale or ended.
--   R  Register: a new customer (with the website's source), an exact match,
--      the same words, held for staff (phone, Gmail inbox, phone and email,
--      several matches, an old unreadable phone), every problem at once and
--      nothing kept, already registered (days added, by the email they used;
--      anyone else who knows a phone and a name gets no link, no days and no
--      names), a guest staff took off stays off, 10 people, the same form
--      again, an id reused, closed; each person is a free guest at once; the
--      answer never says who was matched, made, held or referred (read
--      without its random VIP link tokens, which can spell "held": the
--      owner's point E, 20 Oct 2026).
--   F  Referral: a new person under the link, an existing customer kept as
--      they are, the affiliate themself, a link switched off, an unknown code,
--      the hourly limit; a held person made a customer by staff on a phone in
--      use waits for a check with no referrer yet (Q19 = A; the owner, 21 Oct
--      2026: no commission before it, section FQ); attached, they are not.
--   FS No self-referral (the owner, 20 Oct 2026; narrowed ~20:15; 21 Oct
--      2026): the affiliate through her own link is nobody's referral and
--      earns nothing, whether she is found by her name in other words (a
--      phone and email not on file: held for staff under To match, her record
--      the one to link) or her own record (staff attach a held one to it), on
--      a form whose other people are still referred; a name like hers but not
--      hers is referred; someone else on her phone or her email inbox, or on
--      another customer's phone, is held and, made a customer, waits for a
--      check (not "self"); her VIP paid while she is held waits, and linked to
--      her record earns her upline tier-1 once and her nothing (the real
--      referral's on the same payment earns hers); someone else with her
--      name, made a new customer by staff, is not referred and their VIP earns
--      nobody anything; staff see a plain note ("She earns no commission from
--      it" on her own row; Guests, To match, the Website tab's test
--      registrations, one audit row); the test key says the same and writes
--      nothing. Someone else's existing
--      record is not her (the review of round 4): a customer she already
--      referred, on her phone, through her link is already a customer (a
--      duplicate event; the note says his referral stands) and his VIP
--      still pays her; a held person on her email inbox whom staff attach
--      to their own record is already a customer (the note says none is
--      added). Through her link switched off (the review of 21 Oct 2026):
--      her name on a new phone and email is held the same way; linked to her
--      record she is herself and her VIP earns her upline; someone else with
--      her name made a customer is not referred; the test key says the same.
--   FA The owner's answers, 20 Oct 2026, ~20:15, on one form through an
--      affiliate's link: (A) her mother on her phone and a friend on her
--      Gmail inbox are held; made customers by staff they wait for 425's
--      check (no referrer, a pending check naming her, the sign-up counted
--      for the link, audited, a note); their VIP paid meanwhile earns
--      nothing; an Owner checks the mother as a different person: referred
--      (dated when made a customer), her VIP then earns the affiliate's and
--      the upline's commission, and she counts in a referral promotion; a
--      Manager checks the friend as the same person: never referred, nothing
--      earned; staff cannot decide; a second decision changes nothing; a
--      relative checked first earns on a VIP bought later at once; one
--      merged into an older record before the check is referred by nobody
--      (the note says why); a part refund recorded while the check waited is
--      taken off when it earns (as a plain referral's with the same refund);
--      an older record merged INTO the one made for them before the check
--      makes them an existing customer (D: not referred, a note; a record
--      made after theirs does not); checked but not referred, the note says
--      why (the affiliate's record deleted, another referrer). (B) the
--      affiliate under her name in other words on a new phone and email (held
--      for staff, her record to link: the owner, 21 Oct 2026), and under her
--      own name on a new phone with her own email, is herself. (C) her own
--      VIP earns her upline. (D) a customer another affiliate already
--      referred keeps that referral, with a note. A new person on the form is
--      referred as usual; the test key says the same for each person and
--      writes nothing.
--   FQ The owner's answer, 21 Oct 2026, on Q19 for another customer's phone:
--      the two made customers on Rosa's phone through the link earn nothing
--      on a VIP paid while their checks wait; staff cannot decide; checked as
--      a different person by an Owner: referred, and the VIP then earns the
--      affiliate's and the upline's commission once; checked as the same
--      person by a Manager: never referred, nothing earned; the notes.
--   V  VIP through HitPay: one payment for three people is three invoices
--      (the VIP ticket, the vouchers free), three payments with one reference,
--      the vouchers on each person's own account, commission for the referred
--      person only, the free records parked, the VIP records on both days with
--      the check-ins; replays; the amount; a held person's payment waits and is
--      invoiced once staff match them; already VIP; off sale after paying;
--      Record only; the times; HitPay's sandbox with the live key, a real
--      payment with the test key; the test key changes nothing.
--   T  PayNow and bank transfers: recorded, every reason they wait, Create
--      invoices (with the amount that arrived, Owner or Manager), dismiss and
--      restore, close as refunded and reopen; the same order sent again; a
--      Manager of another of the event's stores cannot act on them.
--   X  Refunds: a VIP invoice cancelled takes the vouchers back, cancels the
--      VIP record and brings the free one back with its check-ins, reverses
--      the commission; reopened, VIP again; HitPay's refund notice; an old
--      VIP invoice is not reopened while a newer VIP stands.
--   XF Refunded in full (the owner, 20 Oct 2026): "Refund in full" takes back
--      the unused S$72 and 3-in-1 vouchers as Cancel does, and the plan says
--      so first; one already used is named first (the refund needs a
--      reason) and stays recorded; a part refund changes nothing until the
--      rest is refunded; Cancel (its refund recorded first) is as before; a
--      refund straight from the Finance panel; replays; VIP bought again
--      after the refund is paid for and gives one set; limited voucher stock
--      back once; a part refund's plan; a voucher moved to another customer
--      is not "used" (its replacement is taken back, or named once used);
--      the invoice reopened reads pending and no second VIP is sold over it;
--      the Finance panel refuses a VIP ticket refund once a voucher is used
--      (a part refund still goes; a later change is not refused); a paid
--      voucher line is the normal refund flow's; a deleted invoice changes
--      nothing.
--   XR The owner's answers, round 3 (20 Oct 2026): a VIP voucher (SAVE72)
--      already used on a later invoice that is not cancelled or deleted (as
--      the invoice's discount voucher or a line's voucher) stops a full
--      refund of the VIP on every path, naming that invoice: Refund in full
--      and a part refund that pays the ticket back in full, the approval of
--      a request raised before, the Finance panel; an invoice before the VIP
--      invoice, a deleted, a cancelled or another customer's one does not;
--      an Owner or a Manager still records a part refund in the Finance
--      panel (the rest is refused). VIPs sold at the counter (the VIP ticket
--      with SAVE72 and the 3-in-1 as free lines): taken back on Refund in
--      full and from the Finance panel, the later-use and recorded-use rules
--      apply, a free voucher that is not a VIP voucher stays, the VIP ticket
--      with only such a voucher is a normal refund. Refunded (or cancelled),
--      reopened, paid again and refunded again (the Finance panel; the
--      guided Refund in full): nothing reads as used. Cancel too: asked for
--      before the later invoice (its approval) or after (the request); a
--      direct cancellation goes, recording all its refund due does not. A
--      counter VIP for two takes back each VIP's share (two lines, one line
--      of two; S$71.99 back is not a ticket). A SAVE72 given while the VIP
--      stood refunded is not counted once it is reopened and paid again. A
--      part refund of another line is not blocked; a payment corrected after
--      an earlier ticket refund is not refused. Since the owner's answer of 21 Oct 2026
--      the guided paths carry an Owner's or Manager's override instead of a
--      blocker (the approval refuses it without a reason; staff never approve).
--   XO The owner's answer, 21 Oct 2026: the Owner and a Manager each allow a
--      VIP's full refund (the Owner asking herself; staff asking) with a
--      reason, refused without one, never by staff (nor the Finance panel's
--      refund); the reason on the approval and in the audit log, a row on the
--      VIP invoice naming the later invoice and a second giving the reason
--      once the approval is stored; a Cancel allowed so, its money recorded
--      as paid back afterwards; a Cancel approved before any later discount:
--      a SAVE72 given after the cancellation is not counted (the review of
--      21 Oct 2026).
--   G  Gifts at the door: one per VIP, out of the store's stock by Record use,
--      refused for others, without store access, out of stock, twice; replay;
--      undone by a Manager.
--   Y  Sync: the website people, staff guests, counter tickets, VIP states and
--      orders; too soon; a test key sees test rows only; the nudge.
--   H  To match on the Event page: the list and its candidates; close; 50
--      people waiting among production-sized customers, read quickly.
--   D  Guards: deleting the event; a deleted event's keys revoked and refused;
--      a merge moves the person's customer.
--   PL Planning answers (the owner, 21 Oct 2026, round 7): on a dedicated
--      event, the talk titles (the suggested list until an Owner, Admin or
--      Manager saves the event's own; staff and other stores cannot; limits;
--      audited; [] and back), each person's answers by their own link token
--      (people on their own, in order: saved, replayed, unchanged, a new
--      version, changed_meanwhile, day_not_chosen, outside_hours (half hours
--      within the hours; a whole day from start to end; no hours; hours moved:
--      a kept time passes), talk_not_offered (a kept title passes), unknown
--      tokens), one form for every answer on the website and staff paths, a
--      direct call outside the contract refused (class 22), answers following
--      a VIP to their VIP record and its days, people taken off the list,
--      closed or held (they answer as anyone), the website Off and the event
--      off sale (answers go on) and the event's end (closed), the test key's
--      dry run, the own budget of 300, the Event page (who sees and changes
--      answers, versions, notes, the audit, staff of other stores, a counter
--      VIP's answers through a correction), the summary (per day, the VIPs
--      and those still paying, talks, how they heard, questions), person and
--      sync (a website person's own; staff and counter guests' never), no
--      answer naming who anyone is, and when answers close.
--   RQ The owner's answers to round 6 (21 Oct 2026): someone held only for
--      another customer's email inbox waits for the check like answer 2
--      (R6-1), and the commission on a VIP paid meanwhile is dated the day of
--      the check (R6-5); the affiliate held under her name through her link
--      switched off and linked to her record reads 'self' (R6-6, in FS10); a
--      SAVE72 given before a cancellation still counts after the reopening
--      (R6-7, XR10).
--   DV Two VIP payments for one customer (the owner, 21 Oct 2026, round 8:
--      P1): a To match candidate already a guest of the event shows their
--      days and VIP payments (paid with its invoice, or waiting), one who
--      is not shows none, and the held person's own payment (a transfer
--      waiting; an unpaid checkout is none); a customer with a website VIP
--      paid and a counter VIP not paid, and one linked to a held person
--      whose transfer waits (then confirmed): their guest rows flagged,
--      vip_doubles and the Planning VIP block name them, the summary counts
--      them once; one cancelled, no longer flagged; the helper is the
--      server's. The review of round 8: a counter VIP with no answers
--      linked to a held person who answered (her transfer waiting) keeps
--      her answers, allergy included (DV7); two transfers waiting on two
--      free records of one customer, one per day, count on both days (DV8).
--   P  Grants: nothing for anon; the page's functions for signed-in staff
--      (each checks the caller); the rest and the tables the server's.
--   M  436 twice changes nothing (when this file installs it).
--
-- Every check runs, then the file fails if any did. Disposable database only;
-- everything is rolled back. Everything here runs in ONE transaction, so now()
-- is one moment: what depends on one action coming after another in time (an
-- approval and a later invoice, a cancellation and a later discount, the
-- approval's setting invoice.therapy_reviewed) is also run action by action,
-- in separate transactions, by event-website-separate-tx.sql beside this file. It installs supabase/436 itself, twice (run with
-- -v skip_install=1 where it is already installed). Every name and email is
-- invented; phones are ACMA's fictional ranges (+61 2 5550 ...., +61 491 57x
-- xxx), Singapore-style only for the old-phone case.
\set ON_ERROR_STOP on
begin;
\if :{?skip_install}
\else
\ir ../../../supabase/436_event_website_registrations_and_vip.sql
create temp table m436 as
  select p.oid::regprocedure::text as fn, md5(pg_get_functiondef(p.oid)) as md5
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f';
\ir ../../../supabase/436_event_website_registrations_and_vip.sql
\endif
set local lock_timeout = '10s';
set local statement_timeout = '300s';
create temp table failed(n serial, msg text);
create function pg_temp.check(ok boolean, msg text) returns void language plpgsql as
$$begin
  if ok is distinct from true then insert into failed(msg) values (msg); raise notice 'FAIL  %', msg;
  else raise notice 'PASS  %', msg; end if;
end$$;
create temp table fx(k text primary key, v uuid);
create temp table tx(k text primary key, v text);
create function pg_temp.fx(key text) returns uuid language sql as $$ select v from fx where k = key $$;
create function pg_temp.tx(key text) returns text language sql as $$ select v from tx where k = key $$;
create function pg_temp.put(key text, val text) returns void language sql as
$$ insert into tx values (key, val) on conflict (k) do update set v = excluded.v $$;
create function pg_temp.putx(key text, val uuid) returns void language sql as
$$ insert into fx values (key, val) on conflict (k) do update set v = excluded.v $$;
-- A browser request carries its login and the role authenticated; the edge
-- function calls as the service role, with no login.
create function pg_temp.as_user(key text) returns void language sql as
$$ select set_config('request.jwt.claim.sub', coalesce(pg_temp.fx(key)::text, ''), true),
          set_config('request.jwt.claim.role', 'authenticated', true) $$;
create function pg_temp.as_service() returns void language sql as
$$ select set_config('request.jwt.claim.sub', '', true), set_config('request.jwt.claim.role', 'service_role', true) $$;
create function pg_temp.err(q text) returns text language plpgsql as
$$begin execute q; return 'ok'; exception when others then return sqlerrm; end$$;
create function pg_temp.errcode(q text) returns text language plpgsql as
$$begin execute q; return 'ok'; exception when others then return sqlstate; end$$;
create function pg_temp.d(n int) returns date language sql as $$ select public.sg_today() + n $$;
-- Fictional phones: +61 2 5550 nnnn (ACMA's drama range), one block per run.
create function pg_temp.ph(n int) returns text language sql as
$$ select '+6125550' || lpad(((pg_temp.tx('phbase')::int + n) % 10000)::text, 4, '0') $$;
create function pg_temp.mail(tag text) returns text language sql as
$$ select 'ht436-' || lower(tag) || '-' || lower(pg_temp.tx('sfx')) || '@example.com' $$;
create function pg_temp.bid(prefix text, tag text) returns text language sql as
$$ select prefix || '-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || upper(substr(md5(pg_temp.tx('sfx') || prefix || tag), 1, 8)) $$;
create function pg_temp.person(pos int, first text, last text, phone text, email text, days date[], vip boolean default false)
returns jsonb language sql as
$$ select jsonb_build_object('position', pos, 'first_name', first, 'last_name', last, 'phone', phone, 'email', email,
            'days', to_jsonb(days), 'vip', vip) $$;
-- One message as the edge function hands it in, with the key of that kind.
create function pg_temp.call(kind text, typ text, body jsonb, req uuid default gen_random_uuid()) returns jsonb
language plpgsql as $$
declare v jsonb; v_sub text := current_setting('request.jwt.claim.sub', true); v_role text := current_setting('request.jwt.claim.role', true);
begin
  perform pg_temp.as_service();
  v := public.event_web_call(pg_temp.tx('hash:' || kind), case when typ in ('event_info','referral_info','person','sync') then null else req end,
                             typ, jsonb_build_object('type', typ, 'event', coalesce(body->>'event', pg_temp.tx('code'))) || (body - 'event'));
  perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_role, ''), true);
  return v;
end $$;
create function pg_temp.register(kind text, tag text, people jsonb, code text default null, req uuid default gen_random_uuid())
returns jsonb language sql as
$$ select pg_temp.call(kind, 'register', jsonb_build_object('registration', jsonb_build_object(
     'registration_id', pg_temp.bid('REG', tag), 'submitted_at', now(), 'referral_code', code, 'people', people)), req) $$;
create function pg_temp.pid(answer jsonb, pos int) returns uuid language sql as
$$ select (x->>'person_id')::uuid from jsonb_array_elements(answer->'people') x where (x->>'position')::int = pos $$;
create function pg_temp.tok(answer jsonb, pos int) returns text language sql as
$$ select x->>'upgrade_token' from jsonb_array_elements(answer->'people') x where (x->>'position')::int = pos $$;
-- An answer with its random values set aside (each person's VIP link token and
-- id), so a word check reads only its keys and fixed values: a token is 26
-- random letters and digits and can spell "held" (about 1 run in 6,000 failed
-- by chance before, the owner's point E, 20 Oct 2026). A token that is not
-- one is left in, so it is still read.
create function pg_temp.fixed_part(answer jsonb) returns text language sql as
$$ select (answer - 'people' || jsonb_build_object('people', coalesce(jsonb_agg(
             x || case when x->>'upgrade_token' ~ '^vip_[a-z2-7]{26}$' then '{"upgrade_token": "TOKEN"}'::jsonb else '{}'::jsonb end
               || case when x->>'person_id' ~ '^[0-9a-f-]{36}$' then '{"person_id": "ID"}'::jsonb else '{}'::jsonb end
             order by (x->>'position')::int), '[]'::jsonb)))::text
     from jsonb_array_elements(coalesce(answer->'people', '[]'::jsonb)) x $$;
create function pg_temp.says_who(answer jsonb) returns boolean language sql as
$$ select pg_temp.fixed_part(answer) ~* 'customer|held|match|referr|exact|same_words' $$;
create function pg_temp.pp(id uuid) returns public.event_registration_people language sql as
$$ select * from public.event_registration_people where id = $1 $$;
create function pg_temp.guest(id uuid) returns public.event_guests language sql as
$$ select * from public.event_guests where id = $1 $$;
create function pg_temp.checkout(kind text, tag text, tokens text[], live boolean default true, opened timestamptz default null)
returns jsonb language sql as
$$ select pg_temp.call(kind, 'vip_checkout', jsonb_build_object('order', jsonb_build_object(
     'order_id', pg_temp.bid('VIP', tag), 'upgrade_tokens', to_jsonb(tokens),
     'payer', jsonb_build_object('name', 'Payer ' || tag, 'email', pg_temp.mail('payer-' || tag), 'phone', null),
     'livemode', live, 'checkout_opened_at', coalesce(opened, now() - interval '3 minutes')))) $$;
create function pg_temp.paid(kind text, tag text, tokens text[], cents int, live boolean default true,
                             paid_at timestamptz default null, req uuid default gen_random_uuid())
returns jsonb language sql as
$$ select pg_temp.call(kind, 'vip_paid', jsonb_build_object('payment', jsonb_build_object(
     'order_id', pg_temp.bid('VIP', tag), 'provider', 'hitpay',
     'payment_request_id', (substr(md5(tag || pg_temp.tx('sfx')), 1, 8) || '-' || substr(md5(tag || pg_temp.tx('sfx')), 9, 4) || '-4'
                             || substr(md5(tag || pg_temp.tx('sfx')), 14, 3) || '-a' || substr(md5(tag || pg_temp.tx('sfx')), 18, 3) || '-'
                             || substr(md5(tag || pg_temp.tx('sfx')), 21, 12)),
     'payment_id', (substr(md5('p' || tag || pg_temp.tx('sfx')), 1, 8) || '-' || substr(md5('p' || tag || pg_temp.tx('sfx')), 9, 4) || '-4'
                    || substr(md5('p' || tag || pg_temp.tx('sfx')), 14, 3) || '-a' || substr(md5('p' || tag || pg_temp.tx('sfx')), 18, 3) || '-'
                    || substr(md5('p' || tag || pg_temp.tx('sfx')), 21, 12)),
     'amount_cents', cents, 'currency', 'SGD', 'livemode', live, 'paid_at', coalesce(paid_at, now() - interval '1 minute'),
     'upgrade_tokens', to_jsonb(tokens),
     'payer', jsonb_build_object('name', 'Payer ' || tag, 'email', pg_temp.mail('payer-' || tag), 'phone', null))), req) $$;
create function pg_temp.transfer(kind text, tag text, tokens text[], method text, cents int, paid_on date,
                                 phone text default null, ref text default null)
returns jsonb language sql as
$$ select pg_temp.call(kind, 'vip_transfer', jsonb_build_object('order', jsonb_build_object(
     'order_id', pg_temp.bid('VIP', tag), 'upgrade_tokens', to_jsonb(tokens),
     'payer', jsonb_build_object('name', 'Payer ' || tag, 'email', pg_temp.mail('payer-' || tag), 'phone', phone),
     'method', method, 'reference', coalesce(ref, 'REF ' || tag), 'paid_on', paid_on, 'amount_cents', cents,
     'submitted_at', now()))) $$;
create function pg_temp.vorder(tag text) returns public.event_vip_orders language sql as
$$ select * from public.event_vip_orders where order_id = pg_temp.bid('VIP', tag) $$;
create function pg_temp.vinvoices(tag text) returns setof public.invoices language sql as
$$ select i.* from public.event_vip_order_people op join public.event_vip_orders o on o.id = op.order_ref
     join public.invoices i on i.id = op.invoice_id where o.order_id = pg_temp.bid('VIP', tag) order by op.position $$;

-- ═════ Fixtures ═════
do $$
declare sfx text := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  u uuid; k text; st uuid; st2 uuid; ev uuid; ev2 uuid; src uuid; pm uuid; v1 uuid; v2 uuid; p1 uuid; p2 uuid; p3 uuid;
  c uuid; a uuid;
begin
  insert into tx values ('sfx', sfx), ('phbase', (floor(random() * 9000))::int::text);
  foreach k in array array['owner', 'acting', 'manager', 'admin', 'staff', 'staff2', 'invmgr', 'manager2'] loop
    u := gen_random_uuid();
    insert into auth.users(id, email) values (u, 'ht436-' || k || '-' || lower(sfx) || '@example.com');
    insert into profiles(id, full_name, email, role, is_active)
    values (u, 'HT436 ' || initcap(k) || ' ' || sfx, 'ht436-' || k || '-' || lower(sfx) || '@example.com',
            case k when 'owner' then 'owner' when 'acting' then 'owner' when 'manager' then 'manager'
                   when 'manager2' then 'manager' when 'admin' then 'admin' when 'invmgr' then 'inventory_manager'
                   else 'staff' end::user_role, true);
    insert into fx values (k, u);
  end loop;
  insert into app_settings(id) values (true) on conflict (id) do nothing;
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  insert into stores(name, code, country_code) values ('HT436 Van ' || sfx, 'HT436V' || sfx, 'SG') returning id into st;
  insert into stores(name, code, country_code) values ('HT436 Shop ' || sfx, 'HT436S' || sfx, 'SG') returning id into st2;
  insert into fx values ('van', st), ('shop', st2);
  insert into user_store_assignments(user_id, store_id) values
    (pg_temp.fx('manager'), st), (pg_temp.fx('staff'), st), (pg_temp.fx('staff2'), st2), (pg_temp.fx('manager2'), st2),
    (pg_temp.fx('invmgr'), st);
  ev := public.event_save(jsonb_build_object('name', 'HT436 Health Seminar ' || sfx,
    'daily_start', '09:00', 'daily_end', '19:00',
    'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(7), 'capacity', 50), jsonb_build_object('day', pg_temp.d(8))),
    'store_ids', jsonb_build_array(st),
    'options', jsonb_build_array(jsonb_build_object('name', 'VIP', 'days_count', 2, 'price', 72))));
  insert into fx values ('ev', ev), ('vip', (select id from public.event_ticket_options where event_id = ev));
  ev2 := public.event_save(jsonb_build_object('name', 'HT436 Other ' || sfx,
    'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(9))), 'store_ids', jsonb_build_array(st2),
    'options', jsonb_build_array(jsonb_build_object('name', 'Entry', 'days_count', 1, 'price', 10))));
  insert into fx values ('ev2', ev2);
  insert into customer_source_options(label, is_active, requires_details, sort_order)
  values ('HT436 Event ' || sfx, true, true, 9999) returning id into src;
  insert into fx values ('src', src);
  -- One active method per name (429 keeps names unique among live methods).
  foreach k in array array['HitPay (online)', 'PayNow', 'Bank Transfer'] loop
    pm := null;
    select id into pm from public.payment_methods where lower(btrim(name)) = lower(k) and deleted_at is null order by created_at limit 1;
    if pm is null then insert into public.payment_methods(name, is_active) values (k, true) returning id into pm;
    else update public.payment_methods set is_active = true where id = pm; end if;
    insert into fx values (case k when 'PayNow' then 'paynow' when 'Bank Transfer' then 'bank' else 'hitpay' end, pm);
  end loop;
  -- The two VIP vouchers: a S$72 offset (fixed discount) and a 3-in-1 (normal).
  insert into vouchers(name, code, voucher_kind, discount_amount, qty_type, selling_price, is_active)
  values ('HT436 $72 discount Voucher', 'HT436SAVE72' || sfx, 'fixed_discount', 72, 'unlimited', 72, true) returning id into v1;
  insert into vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
  values ('HT436 3-in-1 Vouchers', 'HT436-3IN1' || sfx, 'normal', 'unlimited', 216, true) returning id into v2;
  insert into fx values ('save72', v1), ('three', v2);
  -- 3-in-1 priced at the van now; the S$72 one only later (as production on 20 Oct).
  insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (v2, st, 216, true);
  insert into products(name, sku, product_type) values ('HT436 Socks Black', 'HT436-SB-' || sfx, 'own') returning id into p1;
  insert into products(name, sku, product_type) values ('HT436 Gloves', 'HT436-GL-' || sfx, 'own') returning id into p2;
  insert into products(name, sku, product_type) values ('HT436 Socks White', 'HT436-SW-' || sfx, 'own') returning id into p3;
  insert into store_inventory(store_id, product_id, current_qty) values (st, p1, 3), (st, p2, 1), (st, p3, 0);
  insert into fx values ('socks', p1), ('gloves', p2), ('white', p3);
  -- The affiliate whose link people come through, and a second whose link is off.
  insert into customers(full_name, phone, email) values ('Aff Testlink', pg_temp.ph(900), pg_temp.mail('aff')) returning id into a;
  insert into customer_affiliates(customer_id, status, referral_code) values (a, 'active', 'HT' || sfx);
  insert into fx values ('aff', a);
  insert into tx values ('code_ok', 'HT' || sfx);
  -- The affiliate's own referrer (tier 2).
  insert into customers(full_name, phone) values ('Aff Upline', pg_temp.ph(901)) returning id into c;
  update customers set referred_by = c where id = a;
  insert into fx values ('upline', c);
  insert into customers(full_name, phone) values ('Aff Paused', pg_temp.ph(902)) returning id into c;
  insert into customer_affiliates(customer_id, status, manually_suspended, referral_code) values (c, 'active', true, 'HP' || sfx);
  insert into tx values ('code_off', 'HP' || sfx);
  -- Customers already on record, for matching.
  insert into customers(full_name, phone, email) values ('Mei Ling Tan', pg_temp.ph(1), null) returning id into c; insert into fx values ('c_exact', c);
  insert into customers(full_name, phone, email) values ('Lim Wei Jie', pg_temp.ph(2), 'old-' || pg_temp.mail('weijie')) returning id into c; insert into fx values ('c_words', c);
  insert into customers(full_name, phone) values ('Rosa Holder', pg_temp.ph(3)) returning id into c; insert into fx values ('c_phone', c);
  insert into customers(full_name, phone, email) values ('Gina Inbox', pg_temp.ph(4), 'gi.na.ht' || lower(sfx) || '@gmail.com') returning id into c; insert into fx values ('c_mail', c);
  insert into customers(full_name, phone) values ('Sam Twin', pg_temp.ph(5)) returning id into c; insert into fx values ('c_twin1', c);
  insert into customers(full_name, phone) values ('Ken Existing', pg_temp.ph(6)) returning id into c; insert into fx values ('c_ken', c);
  insert into customers(full_name, phone) values ('Sam Twin', pg_temp.ph(5)) returning id into c; insert into fx values ('c_twin2', c);
end $$;
-- An old import whose phone cannot be read as one number (written as old imports were). The number is drawn at run
-- time (8 digits starting with 8 that read as Singapore or Malaysia, held by no customer in either form), so no
-- real-format number is written here: an ACMA (+61) number cannot exercise the old 8-digit Singapore path.
insert into tx values ('legacy8', (select s.d from (select '8' || lpad(floor(random() * 1e7)::int::text, 7, '0') as d
                                                      from generate_series(1, 500)) s
                                    where public.normalize_customer_phone(s.d) is null
                                      and (public.inspect_customer_phone(s.d)->'candidates') ? ('+65' || s.d)
                                      and not exists (select 1 from customers c
                                                       where regexp_replace(coalesce(c.phone, ''), '\D', '', 'g')
                                                             in (s.d, '65' || s.d, '60' || s.d))
                                    limit 1));
create function pg_temp.legacy8_sg() returns text language sql as
$$ select '+65 ' || substr(pg_temp.tx('legacy8'), 1, 4) || ' ' || substr(pg_temp.tx('legacy8'), 5) $$;
alter table customers disable trigger zz_normalize_current_customer_phone;
do $$ declare c uuid; begin
  insert into customers(full_name, phone) values ('Ong Testlegacy', pg_temp.tx('legacy8')) returning id into c; insert into fx values ('c_legacy', c);
end $$;
alter table customers enable trigger zz_normalize_current_customer_phone;

-- ═════ S Settings and keys ═════
select pg_temp.as_user('owner');
create function pg_temp.settings(mode text default 'off', code text default null) returns jsonb language sql as
$$ select jsonb_build_object('code', coalesce(code, 'HT436-' || pg_temp.tx('sfx')), 'mode', mode, 'venue', null,
     'store_id', pg_temp.fx('van'), 'acting_profile_id', pg_temp.fx('acting'), 'vip_option_id', pg_temp.fx('vip'),
     'vip_voucher_ids', jsonb_build_array(pg_temp.fx('save72'), pg_temp.fx('three')),
     'gift_product_ids', jsonb_build_array(pg_temp.fx('socks'), pg_temp.fx('gloves'), pg_temp.fx('white')),
     'hitpay_payment_method_id', pg_temp.fx('hitpay'), 'paynow_payment_method_id', pg_temp.fx('paynow'),
     'bank_payment_method_id', pg_temp.fx('bank'), 'source_option_id', pg_temp.fx('src'),
     'source_details', 'Health Seminar (website)', 'sync_url', 'https://healthtalk.example.com/api/app/sync') $$;
insert into tx values ('code', 'HT436-' || pg_temp.tx('sfx'));
select pg_temp.put('s_off', pg_temp.err(format('select public.event_web_settings_save(%L, %L)', pg_temp.fx('ev'), pg_temp.settings('off'))));
select pg_temp.put('s_on', pg_temp.err(format('select public.event_web_settings_save(%L, %L)', pg_temp.fx('ev'), pg_temp.settings('live'))));
select pg_temp.check(pg_temp.tx('s_off') = 'ok' and (select mode from public.event_web_settings where event_id = pg_temp.fx('ev')) = 'off'
    and pg_temp.tx('s_on') like 'Before the website can be switched on: "HT436 $72 discount Voucher" has no price at the store%',
  'S1 settings save while Off with a voucher not priced at the store; switching on is refused, naming it: ' || pg_temp.tx('s_on'));
select pg_temp.check((public.event_web_readiness(pg_temp.fx('ev'))->'warnings') @> '["A day has a capacity. The website never shows it, and does not stop at it.", "No live key yet.", "The talk titles are the suggested list: set the real ones under Talk titles once the speakers'' titles are known."]'::jsonb
    and (public.event_web_readiness(pg_temp.fx('ev'))->'warnings') ? '"HT436 Socks White" has no stock at the store.',
  'S1 readiness warns: a capacity set, no live key, a gift with no stock, the talk titles still the suggested list (round 7)');
update public.events set daily_start = null where id = pg_temp.fx('ev');
select pg_temp.put('s1_hours', (public.event_web_readiness(pg_temp.fx('ev'))->'warnings')::text);
update public.events set daily_start = '09:00' where id = pg_temp.fx('ev');
select pg_temp.check((pg_temp.tx('s1_hours')::jsonb) ? 'The event has no start or finish time, so the website shows no hours: set them with Edit event.'
    and not ((public.event_web_readiness(pg_temp.fx('ev'))->'warnings') ? 'The event has no start or finish time, so the website shows no hours: set them with Edit event.'),
  'S1 readiness warns when the event has no start or finish time (the website would show no hours), and not once they are set');
insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (pg_temp.fx('save72'), pg_temp.fx('van'), 72, true);
-- (Each action runs in a statement of its own: a check reads what the statements before it did.)
select pg_temp.put('s_live', pg_temp.err(format('select public.event_web_settings_save(%L, %L)', pg_temp.fx('ev'), pg_temp.settings('live'))));
select pg_temp.check(pg_temp.tx('s_live') = 'ok'
    and (select (mode, vip_voucher_ids) = ('live', array[pg_temp.fx('save72'), pg_temp.fx('three')])
           from public.event_web_settings where event_id = pg_temp.fx('ev')),
  'S1 once the voucher has a price the Owner switches it Live; the vouchers keep their order');
select pg_temp.check(pg_temp.err(format('select public.event_web_settings_save(%L, %L)', pg_temp.fx('ev'), pg_temp.settings('off', 'ab'))) like 'The event code is 3 to 40 capital letters%'
    and pg_temp.err(format('select public.event_web_settings_save(%L, %L)', pg_temp.fx('ev'),
          pg_temp.settings('off') || jsonb_build_object('store_id', pg_temp.fx('shop')))) = 'The store is not one of the event''s stores.'
    and pg_temp.err(format('select public.event_web_settings_save(%L, %L)', pg_temp.fx('ev'),
          pg_temp.settings('off') || jsonb_build_object('sync_url', 'http://x.example.com'))) = 'The sync URL must start with https://',
  'S2 a bad code, a store that is not the event''s, an http sync URL: refused');
select pg_temp.as_user('owner');
select pg_temp.put('ev2_save', pg_temp.err(format('select public.event_web_settings_save(%L, %L)', pg_temp.fx('ev2'),
  pg_temp.settings('off') || jsonb_build_object('store_id', pg_temp.fx('shop'), 'vip_option_id', null))));
select pg_temp.check(pg_temp.tx('ev2_save') = 'Another event''s website already uses the code ' || pg_temp.tx('code'),
  'S2 a code another event''s website uses: refused');
select pg_temp.as_user('manager');
select pg_temp.put('s3_venue', pg_temp.err(format('select public.event_web_set_venue(%L, %L)', pg_temp.fx('ev'), 'Hall 1, Example Centre')));
select pg_temp.check(pg_temp.errcode(format('select public.event_web_settings_save(%L, %L)', pg_temp.fx('ev'), pg_temp.settings('live'))) = '42501'
    and pg_temp.errcode(format('select public.event_web_key_create(%L, ''live'', null)', pg_temp.fx('ev'))) = '42501'
    and pg_temp.tx('s3_venue') = 'ok'
    and (select venue from public.event_web_settings where event_id = pg_temp.fx('ev')) = 'Hall 1, Example Centre'
    and (public.event_web_settings_get(pg_temp.fx('ev'))->>'can_manage')::boolean = false,
  'S3 a Manager cannot save settings or make a key, but sets the venue and reads the tab (can_manage false)');
select pg_temp.as_user('staff');
select pg_temp.check(pg_temp.errcode(format('select public.event_web_settings_get(%L)', pg_temp.fx('ev'))) = '42501'
    and pg_temp.errcode(format('select public.event_web_set_venue(%L, null)', pg_temp.fx('ev'))) = '42501',
  'S3 staff neither read the Website tab nor set the venue');
select pg_temp.as_user('manager2');
select pg_temp.check(pg_temp.errcode(format('select public.event_web_settings_get(%L)', pg_temp.fx('ev'))) = '42501',
  'S3 a Manager of another store does not read it');
select pg_temp.as_user('owner');
select public.event_web_set_venue(pg_temp.fx('ev'), null);
do $$ declare r jsonb; begin
  perform pg_temp.as_user('owner');
  r := public.event_web_key_create(pg_temp.fx('ev'), 'live', 'Vercel production');
  insert into tx values ('key:live', r->>'key'), ('hint:live', r->>'key_hint');
  insert into fx values ('key_live', (r->>'key_id')::uuid);
  insert into tx values ('hash:live', encode(extensions.digest(r->>'key', 'sha256'), 'hex'));
  r := public.event_web_key_create(pg_temp.fx('ev'), 'test', 'Vercel preview');
  insert into tx values ('key:test', r->>'key'), ('hash:test', encode(extensions.digest(r->>'key', 'sha256'), 'hex'));
  insert into fx values ('key_test', (r->>'key_id')::uuid);
  r := public.event_web_key_create(pg_temp.fx('ev'), 'live', 'to revoke');
  insert into tx values ('hash:old', encode(extensions.digest(r->>'key', 'sha256'), 'hex'));
  insert into fx values ('key_old', (r->>'key_id')::uuid);
end $$;
select pg_temp.check(pg_temp.tx('key:live') ~ '^evk_live_[A-Za-z0-9_-]{43}$' and pg_temp.tx('key:test') ~ '^evk_test_[A-Za-z0-9_-]{43}$'
    and (select key_hash from public.event_web_keys where id = pg_temp.fx('key_live')) = pg_temp.tx('hash:live')
    and pg_temp.tx('hint:live') = 'evk_live_' || substr(pg_temp.tx('key:live'), 10, 4) || '…' || right(pg_temp.tx('key:live'), 4)
    and not exists (select 1 from public.event_web_keys k where to_jsonb(k)::text like '%' || pg_temp.tx('key:live') || '%')
    and not exists (select 1 from public.audit_logs a where a.new_data::text like '%' || substr(pg_temp.tx('key:live'), 10) || '%'
                       or coalesce(a.old_data::text, '') like '%' || substr(pg_temp.tx('key:live'), 10) || '%')
    and not ((public.event_web_settings_get(pg_temp.fx('ev')))::text like '%' || substr(pg_temp.tx('key:live'), 10) || '%'),
  'S4 a key is evk_<kind>_ and 43 characters, shown once: only its SHA-256 and a hint are kept, never in the audit log or the tab');
select pg_temp.put('s5_short', pg_temp.err(format('select public.event_web_key_revoke(%L, %L)', pg_temp.fx('key_old'), 'x')));
select pg_temp.put('s5_revoke', pg_temp.err(format('select public.event_web_key_revoke(%L, %L)', pg_temp.fx('key_old'), 'Leaked in a chat')));
select pg_temp.check(pg_temp.tx('s5_short') = 'Give a reason for revoking the key' and pg_temp.tx('s5_revoke') = 'ok'
    and pg_temp.call('old', 'event_info', '{}') = '{"ok": false, "error": "bad_key"}'::jsonb,
  'S5 a revoked key is refused at once (bad_key)');
insert into tx values ('hash:unknown', repeat('ab', 32));
select pg_temp.put('s5_info', pg_temp.call('live', 'event_info', '{}')::text);
select pg_temp.check(pg_temp.call('unknown', 'event_info', '{}') = '{"ok": false, "error": "bad_key"}'::jsonb
    and pg_temp.call('live', 'event_info', '{"event": "OTHER-EVENT"}') = '{"ok": false, "error": "wrong_event"}'::jsonb
    and (pg_temp.tx('s5_info')::jsonb->>'ok')::boolean
    and (select last_used_at is not null from public.event_web_keys where id = pg_temp.fx('key_live')),
  'S5 an unknown key is bad_key, another event''s code wrong_event; the live key answers and notes when it was used');

-- ═════ I event_info ═════
select pg_temp.put('info', pg_temp.call('live', 'event_info', '{}')::text);
select pg_temp.check((pg_temp.tx('info')::jsonb) = jsonb_build_object('ok', true, 'test', false, 'status', 'ok', 'event', jsonb_build_object(
      'code', pg_temp.tx('code'), 'title', 'HT436 Health Seminar ' || pg_temp.tx('sfx'),
      'days', jsonb_build_array(jsonb_build_object('date', pg_temp.d(7), 'label', 'Day 1', 'open', true),
                                jsonb_build_object('date', pg_temp.d(8), 'label', 'Day 2', 'open', true)),
      'daily_start', '09:00', 'daily_end', '19:00', 'time_zone', 'Asia/Singapore', 'venue', null,
      'registration_open', true, 'closed_reason', null, 'talk_titles', null, 'planning_open', true,
      'vip', jsonb_build_object('price_cents', 7200, 'currency', 'SGD', 'on_sale', true, 'covers', 'all_days'))),
  'I1 event_info: the title, both days open, the hours (9 am to 7 pm, the owner''s answer of 20 Oct), no venue yet (to be announced), VIP S$72 for every day: ' || pg_temp.tx('info'));
select pg_temp.check(pg_temp.tx('info') !~* 'capacity|registered"|seats|count',
  'I1 never a capacity or a count (day 1 has a capacity of 50)');
select pg_temp.as_user('owner');
select public.event_web_set_venue(pg_temp.fx('ev'), 'Hall 2, Example Centre');
select pg_temp.check(pg_temp.call('live', 'event_info', '{}')->'event'->>'venue' = 'Hall 2, Example Centre',
  'I1 the venue once it is set');
select pg_temp.as_user('owner');
select pg_temp.put('i1_keep', pg_temp.err(format('select public.event_web_settings_save(%L, %L)', pg_temp.fx('ev'), pg_temp.settings('live') - 'venue')));
select pg_temp.check(pg_temp.tx('i1_keep') = 'ok'
    and (select venue from public.event_web_settings where event_id = pg_temp.fx('ev')) = 'Hall 2, Example Centre',
  'I1 saving the settings without a venue keeps the one set (a Manager may set it on its own)');
update public.events set is_active = false where id = pg_temp.fx('ev');
select pg_temp.check(pg_temp.call('live', 'event_info', '{}')->'event' @> '{"registration_open": false, "closed_reason": "off_sale", "vip": {"on_sale": false}}'::jsonb,
  'I2 the event''s Tickets on sale off: closed (off_sale)');
update public.events set is_active = true where id = pg_temp.fx('ev');
update public.event_web_settings set mode = 'off' where event_id = pg_temp.fx('ev');
select pg_temp.check(pg_temp.call('live', 'event_info', '{}')->'event' @> '{"registration_open": false, "closed_reason": "website_off"}'::jsonb
    and pg_temp.register('live', 'off1', jsonb_build_array(pg_temp.person(1, 'Off', 'Line', pg_temp.ph(60), pg_temp.mail('off'), array[pg_temp.d(7)])))
        = jsonb_build_object('ok', true, 'test', false, 'status', 'closed', 'reason', 'website_off'),
  'I2 the website Off: closed (website_off), and a registration is refused as closed');
update public.event_web_settings set mode = 'live' where event_id = pg_temp.fx('ev');
update public.event_ticket_options set is_active = false where id = pg_temp.fx('vip');
select pg_temp.check(pg_temp.call('live', 'event_info', '{}')->'event' @> '{"registration_open": true, "vip": {"on_sale": false}}'::jsonb,
  'I2 the VIP ticket off sale: registration open, VIP not on sale');
update public.event_ticket_options set is_active = true where id = pg_temp.fx('vip');

-- ═════ R Register ═════
-- R1 a new person: a customer with the website's source, a free guest on their days.
select pg_temp.put('r1', pg_temp.register('live', 'r1', jsonb_build_array(
  pg_temp.person(1, 'Nadia', 'Freshperson', pg_temp.ph(10), pg_temp.mail('nadia'), array[pg_temp.d(7)])))::text);
select pg_temp.putx('p_r1', pg_temp.pid(pg_temp.tx('r1')::jsonb, 1));
select pg_temp.check((pg_temp.tx('r1')::jsonb) = jsonb_build_object('ok', true, 'test', false, 'status', 'registered',
      'registration_id', pg_temp.bid('REG', 'r1'), 'people', jsonb_build_array(jsonb_build_object('position', 1,
        'person_id', pg_temp.fx('p_r1'), 'upgrade_token', pg_temp.tok(pg_temp.tx('r1')::jsonb, 1),
        'days', jsonb_build_array(pg_temp.d(7)), 'already_registered', false, 'vip', 'none')))
    and pg_temp.tok(pg_temp.tx('r1')::jsonb, 1) ~ '^vip_[a-z2-7]{26}$',
  'R1 registered: the person id, a VIP link token, the days, not already registered, not VIP; nothing about the customer: ' || pg_temp.tx('r1'));
select pg_temp.check((select (c.full_name, c.first_name, c.last_name, c.phone, c.email, c.source_option_id, c.source_details, c.referred_by)
                        is not distinct from ('Nadia Freshperson', 'Nadia', 'Freshperson', pg_temp.ph(10), pg_temp.mail('nadia'),
                                              pg_temp.fx('src'), 'Health Seminar (website)', null::uuid)
                        from public.customers c where c.id = (pg_temp.pp(pg_temp.fx('p_r1'))).customer_id)
    and (pg_temp.pp(pg_temp.fx('p_r1'))).match = 'new_customer',
  'R1 a new customer with the name, phone, email and the website''s source');
select pg_temp.check((select (g.source, g.status, g.name, g.phone, g.customer_id, g.registered_by, g.notes)
                        is not distinct from ('free', 'registered', 'Nadia Freshperson', pg_temp.ph(10), (pg_temp.pp(pg_temp.fx('p_r1'))).customer_id,
                                              null::uuid, 'Website · ' || pg_temp.bid('REG', 'r1') || ' · 1 of 1')
                        from public.event_guests g where g.id = (pg_temp.pp(pg_temp.fx('p_r1'))).free_guest_id)
    and (select array_agg(day) from public.event_guest_days where guest_id = (pg_temp.pp(pg_temp.fx('p_r1'))).free_guest_id) = array[pg_temp.d(7)]
    and exists (select 1 from public.audit_logs a where a.record_id = (pg_temp.pp(pg_temp.fx('p_r1'))).free_guest_id
                  and a.action = 'event_guest_added' and a.new_data @> jsonb_build_object('source', 'website', 'registration_id', pg_temp.bid('REG', 'r1'))
                  and a.changed_by = pg_temp.fx('acting')),
  'R1 a free guest at once, on Day 1, noted "Website · REG… · 1 of 1", audited as added by the website (as the acting profile)');
-- R2..R7 matching.
select pg_temp.put('r2', pg_temp.register('live', 'r2', jsonb_build_array(
  pg_temp.person(1, 'Mei Ling', 'Tan', pg_temp.ph(1), pg_temp.mail('meiling'), array[pg_temp.d(7), pg_temp.d(8)]),
  pg_temp.person(2, 'Wei Jie', 'Lim', pg_temp.ph(2), pg_temp.mail('weijie'), array[pg_temp.d(8)]),
  pg_temp.person(3, 'Rosa', 'Different', pg_temp.ph(3), pg_temp.mail('rosa'), array[pg_temp.d(7)]),
  pg_temp.person(4, 'Gina', 'Other', pg_temp.ph(40), 'gina.ht' || lower(pg_temp.tx('sfx')) || '+seminar@googlemail.com', array[pg_temp.d(7)]),
  pg_temp.person(5, 'Sam', 'Twin', pg_temp.ph(5), pg_temp.mail('sam'), array[pg_temp.d(7)]),
  pg_temp.person(6, 'Ong', 'Testlegacy', pg_temp.legacy8_sg(), pg_temp.mail('ong'), array[pg_temp.d(7)]),
  pg_temp.person(7, 'Rosa', 'Again', pg_temp.ph(3), 'gi.na.ht' || lower(pg_temp.tx('sfx')) || '@gmail.com', array[pg_temp.d(7)]),
  pg_temp.person(8, 'Ola', 'Othername', pg_temp.legacy8_sg(), pg_temp.mail('ola'), array[pg_temp.d(8)])))::text);
create function pg_temp.r2(pos int) returns public.event_registration_people language sql as
$$ select pg_temp.pp(pg_temp.pid(pg_temp.tx('r2')::jsonb, pos)) $$;
select pg_temp.check((pg_temp.r2(1)).match = 'exact' and (pg_temp.r2(1)).customer_id = pg_temp.fx('c_exact')
    and (select email from customers where id = pg_temp.fx('c_exact')) = pg_temp.mail('meiling')
    and (select (source_option_id, source_details) = (pg_temp.fx('src'), 'Health Seminar (website)') from customers where id = pg_temp.fx('c_exact'))
    and (select full_name from customers where id = pg_temp.fx('c_exact')) = 'Mei Ling Tan',
  'R2 phone + exact name: linked; the customer''s empty email and source are filled, the name left alone');
select pg_temp.check((pg_temp.r2(2)).match = 'same_words' and (pg_temp.r2(2)).customer_id = pg_temp.fx('c_words')
    and (select email from customers where id = pg_temp.fx('c_words')) = 'old-' || pg_temp.mail('weijie'),
  'R3 the same words in another order: linked; an email already there is kept');
select pg_temp.check(((pg_temp.r2(3)).match, (pg_temp.r2(3)).hold_reason, (pg_temp.r2(3)).customer_id, (pg_temp.r2(3)).candidate_customer_ids)
                       is not distinct from ('held', 'phone_in_use', null::uuid, array[pg_temp.fx('c_phone')])
    and (pg_temp.guest((pg_temp.r2(3)).free_guest_id)).status = 'registered'
    and (pg_temp.guest((pg_temp.r2(3)).free_guest_id)).customer_id is null
    and (select count(*) from customers where phone = pg_temp.ph(3) and deleted_at is null) = 1,
  'R4 a phone a customer has, another name: held for staff (phone_in_use), no customer made, still a guest at once');
select pg_temp.check(((pg_temp.r2(4)).match, (pg_temp.r2(4)).hold_reason, (pg_temp.r2(4)).candidate_customer_ids)
                       is not distinct from ('held', 'email_in_use', array[pg_temp.fx('c_mail')]),
  'R5 the same Gmail inbox (dots, +tag, googlemail.com) on another phone: held (email_in_use)');
select pg_temp.check(((pg_temp.r2(5)).match, (pg_temp.r2(5)).hold_reason) = ('held', 'several_name_matches')
    and (pg_temp.r2(5)).candidate_customer_ids @> array[pg_temp.fx('c_twin1'), pg_temp.fx('c_twin2')],
  'R6 a name that matches two customers on the phone: held (several_name_matches) for both');
select pg_temp.check(((pg_temp.r2(6)).match, (pg_temp.r2(6)).hold_reason, (pg_temp.r2(6)).candidate_customer_ids)
                       is not distinct from ('held', 'legacy_ambiguous', array[pg_temp.fx('c_legacy')]),
  'R7 an old unreadable phone that could be this one, the same name: held (legacy_ambiguous), not refused');
select pg_temp.check(((pg_temp.r2(7)).match, (pg_temp.r2(7)).hold_reason) = ('held', 'phone_and_email_in_use')
    and (pg_temp.r2(7)).candidate_customer_ids @> array[pg_temp.fx('c_phone'), pg_temp.fx('c_mail')],
  'R7 the phone and the email belong to customers: held (phone_and_email_in_use) for both');
select pg_temp.check(((pg_temp.r2(8)).match, (pg_temp.r2(8)).hold_reason, (pg_temp.r2(8)).candidate_customer_ids)
                       is not distinct from ('held', 'phone_in_use', array[pg_temp.fx('c_legacy')]),
  'R7 another name beside an old number that could be this phone (425''s holders): held (phone_in_use) for that customer');
select pg_temp.check(not pg_temp.says_who(pg_temp.tx('r2')::jsonb)
    and (select count(*) from jsonb_array_elements(pg_temp.tx('r2')::jsonb->'people') x where x->>'vip' = 'none') = 8
    and (select bool_and(x->>'upgrade_token' ~ '^vip_[a-z2-7]{26}$') from jsonb_array_elements(pg_temp.tx('r2')::jsonb->'people') x),
  'R  the answer never says who was matched, made, held or referred (its keys and fixed values; the random tokens set aside)');
-- The check reads the answer, not its random tokens: a token that spells the
-- words is set aside, and a word anywhere else is still caught.
select pg_temp.check(not pg_temp.says_who(jsonb_set(pg_temp.tx('r2')::jsonb, '{people,0,upgrade_token}', '"vip_heldmatchexactcustomerrefe"'))
    and pg_temp.tx('r2') !~ 'vip_heldmatchexactcustomerrefe'
    and pg_temp.says_who(jsonb_set(pg_temp.tx('r2')::jsonb, '{people,0,match}', '"held"'))
    and pg_temp.says_who(pg_temp.tx('r2')::jsonb || '{"referred": true}'::jsonb)
    and pg_temp.says_who(jsonb_set(pg_temp.tx('r2')::jsonb, '{people,0,upgrade_token}', '"held for staff"')),
  'R  (point E) a token spelling held, match, exact or customer does not fail the check by chance; a word in a key or a fixed value still does');
-- R8 every problem at once, nothing kept.
select pg_temp.put('r8', pg_temp.register('live', 'r8', jsonb_build_array(
  pg_temp.person(1, 'Bad', 'Phone', '12', pg_temp.mail('bad1'), array[pg_temp.d(7)]),
  pg_temp.person(2, 'Bad', 'Day', pg_temp.ph(81), pg_temp.mail('bad2'), array[pg_temp.d(9)]),
  pg_temp.person(3, 'Twice', 'Person', pg_temp.ph(82), pg_temp.mail('tw1'), array[pg_temp.d(7)]),
  pg_temp.person(4, 'Person', 'Twice', pg_temp.ph(82), pg_temp.mail('tw2'), array[pg_temp.d(8)])))::text);
select pg_temp.check((pg_temp.tx('r8')::jsonb)->>'status' = 'invalid'
    and (select jsonb_agg(jsonb_build_array(x->'position', x->>'field', x->>'code') order by x->'position') from jsonb_array_elements(pg_temp.tx('r8')::jsonb->'problems') x)
        = '[[1, "phone", "phone_not_accepted"], [2, "days", "day_closed"], [4, "people", "same_person_twice"]]'::jsonb
    and not exists (select 1 from public.event_registrations where registration_id = pg_temp.bid('REG', 'r8'))
    and not exists (select 1 from public.event_guests where phone = pg_temp.ph(81)),
  'R8 a phone the policy cannot read, a day that is not the event''s, the same person twice: all at once, nothing kept: ' || pg_temp.tx('r8'));
-- R9 already registered, with the email they used (in capitals): days added, no second record.
select pg_temp.put('r9', pg_temp.register('live', 'r9', jsonb_build_array(
  pg_temp.person(1, 'Freshperson', 'Nadia', pg_temp.ph(10), upper(pg_temp.mail('nadia')), array[pg_temp.d(8)])))::text);
select pg_temp.check(pg_temp.pid(pg_temp.tx('r9')::jsonb, 1) = pg_temp.fx('p_r1')
    and (pg_temp.tx('r9')::jsonb)->'people'->0 @> jsonb_build_object('already_registered', true, 'days', jsonb_build_array(pg_temp.d(7), pg_temp.d(8)))
    and (select array_agg(day order by day) from public.event_guest_days where guest_id = (pg_temp.pp(pg_temp.fx('p_r1'))).free_guest_id)
        = array[pg_temp.d(7), pg_temp.d(8)]
    and (select count(*) from public.event_guests where event_id = pg_temp.fx('ev') and phone = pg_temp.ph(10)) = 1,
  'R9 the same phone, words and email again: the day is added to their record, the same person and link, no second guest');
-- R9b someone else who knows the phone and the name, with another email: "already registered" and nothing more.
select pg_temp.put('r9b', pg_temp.register('live', 'r9b', jsonb_build_array(
  pg_temp.person(1, 'Me', 'Again', pg_temp.ph(12), pg_temp.mail('other-me'), array[pg_temp.d(7)]),
  pg_temp.person(2, 'nadia', 'FRESHPERSON', pg_temp.ph(10), pg_temp.mail('attacker'), array[pg_temp.d(7), pg_temp.d(8)])))::text);
select pg_temp.check((pg_temp.tx('r9b')::jsonb)->'people'->1
        = '{"position": 2, "person_id": null, "upgrade_token": null, "days": null, "already_registered": true, "vip": null}'::jsonb
    and pg_temp.tx('r9b') !~ (pg_temp.pp(pg_temp.fx('p_r1'))).upgrade_token
    and pg_temp.tx('r9b') !~ pg_temp.fx('p_r1')::text
    and (pg_temp.pp(pg_temp.fx('p_r1'))).email = pg_temp.mail('nadia')
    and (pg_temp.pp(pg_temp.fx('p_r1'))).days = array[pg_temp.d(7), pg_temp.d(8)]
    and (select count(*) from public.event_registration_people where phone_norm = pg_temp.ph(10)) = 1
    and (pg_temp.tx('r9b')::jsonb)->'people'->0 @> '{"already_registered": false}'::jsonb
    and (pg_temp.call('live', 'person', jsonb_build_object('upgrade_token', pg_temp.tok(pg_temp.tx('r9b')::jsonb, 1)))->'group') = '[]'::jsonb,
  'R9b another email with someone''s phone and name: already registered, but no link, id, days or VIP state; their record untouched; nobody on that form''s VIP page: ' || pg_temp.tx('r9b'));
-- R12 a guest staff took off the list stays off when the form is sent again (staff put them back).
select pg_temp.put('r12', pg_temp.register('live', 'r12', jsonb_build_array(
  pg_temp.person(1, 'Rita', 'Removed', pg_temp.ph(13), pg_temp.mail('rita'), array[pg_temp.d(7)])))::text);
select pg_temp.as_user('manager');
select public.event_set_guest_cancelled((pg_temp.pp(pg_temp.pid(pg_temp.tx('r12')::jsonb, 1))).free_guest_id, true, 'Removed by staff: abusive');
select pg_temp.put('r12b', pg_temp.register('live', 'r12b', jsonb_build_array(
  pg_temp.person(1, 'Rita', 'Removed', pg_temp.ph(13), pg_temp.mail('rita'), array[pg_temp.d(7), pg_temp.d(8)])))::text);
select pg_temp.check(((pg_temp.guest((pg_temp.pp(pg_temp.pid(pg_temp.tx('r12')::jsonb, 1))).free_guest_id)).status,
                      (pg_temp.guest((pg_temp.pp(pg_temp.pid(pg_temp.tx('r12')::jsonb, 1))).free_guest_id)).cancelled_reason)
                     = ('cancelled'::text, 'Removed by staff: abusive'::text)
    and (select array_agg(day) from public.event_guest_days where guest_id = (pg_temp.pp(pg_temp.pid(pg_temp.tx('r12')::jsonb, 1))).free_guest_id) = array[pg_temp.d(7)]
    and (pg_temp.pp(pg_temp.pid(pg_temp.tx('r12')::jsonb, 1))).days = array[pg_temp.d(7)]
    and (pg_temp.tx('r12b')::jsonb)->'people'->0 @> '{"already_registered": true}'::jsonb
    and pg_temp.call('live', 'person', jsonb_build_object('upgrade_token', pg_temp.tok(pg_temp.tx('r12')::jsonb, 1)))->'person'
        @> '{"can_upgrade": false, "reason": "cancelled"}'::jsonb
    and exists (select 1 from public.audit_logs a where a.record_id = (pg_temp.pp(pg_temp.pid(pg_temp.tx('r12')::jsonb, 1))).free_guest_id
                  and a.action = 'event_guest_register_again_refused'
                  and a.new_data @> jsonb_build_object('registration_id', pg_temp.bid('REG', 'r12b'))),
  'R12 staff took a guest off the list; the form again (their own email) leaves them off, adds no day, and notes the attempt for staff');
-- R10 ten people on one form.
select pg_temp.put('r10', pg_temp.register('live', 'r10', (select jsonb_agg(pg_temp.person(n, 'Group' || n, 'Member', pg_temp.ph(100 + n),
  pg_temp.mail('g' || n), array[pg_temp.d(7)]) order by n) from generate_series(1, 10) n))::text);
select pg_temp.check(jsonb_array_length(pg_temp.tx('r10')::jsonb->'people') = 10
    and (select count(*) from public.event_guests where event_id = pg_temp.fx('ev') and notes like 'Website · ' || pg_temp.bid('REG', 'r10') || ' · % of 10') = 10,
  'R10 ten people on one form: ten guests, each "k of 10"');
-- R11 the same form again, and its id with other people.
select pg_temp.check(pg_temp.register('live', 'r1', jsonb_build_array(
      pg_temp.person(1, 'Nadia', 'Freshperson', pg_temp.ph(10), pg_temp.mail('nadia'), array[pg_temp.d(7)]))) = pg_temp.tx('r1')::jsonb
    and pg_temp.register('live', 'r1', jsonb_build_array(
      pg_temp.person(1, 'Someone', 'Else', pg_temp.ph(11), pg_temp.mail('else'), array[pg_temp.d(7)])))->'problems'->0
        = '{"position": null, "field": "registration_id", "code": "id_reused", "message": "This form was already sent with other people. Open the form again to register them."}'::jsonb,
  'R11 the same form under a new request id answers as it did; its id with other people is id_reused');
-- S6 the request id.
select pg_temp.put('req_s6', gen_random_uuid()::text);
select pg_temp.put('s6a', pg_temp.register('live', 's6', jsonb_build_array(pg_temp.person(1, 'Replay', 'Person', pg_temp.ph(61), pg_temp.mail('rp'), array[pg_temp.d(7)])), null, pg_temp.tx('req_s6')::uuid)::text);
select pg_temp.check(pg_temp.register('live', 's6', jsonb_build_array(pg_temp.person(1, 'Replay', 'Person', pg_temp.ph(61), pg_temp.mail('rp'), array[pg_temp.d(7)])), null, pg_temp.tx('req_s6')::uuid)
        = pg_temp.tx('s6a')::jsonb
    and pg_temp.register('live', 's6', jsonb_build_array(pg_temp.person(1, 'Replay', 'Person', pg_temp.ph(61), pg_temp.mail('rp'), array[pg_temp.d(8)])), null, pg_temp.tx('req_s6')::uuid)
        = '{"ok": false, "error": "request_conflict"}'::jsonb
    and (select count(*) from public.event_guests where phone = pg_temp.ph(61)) = 1
    and pg_temp.call('live', 'register', '{"registration": {}}', null) = '{"ok": false, "error": "invalid_request", "field": "x-energia-request-id"}'::jsonb,
  'S6 the same request id and body: the first answer again; another body: request_conflict; a write without one: refused');
-- S7 the rate limit.
insert into public.event_web_requests (key_id, request_id, type, is_write, body_md5, outcome, received_at)
select pg_temp.fx('key_test'), gen_random_uuid(), 'register', true, 'x', 'registered', now() - interval '9 minutes' from generate_series(1, 120);
select pg_temp.put('s7', pg_temp.register('test', 's7', jsonb_build_array(pg_temp.person(1, 'Rate', 'Limited', pg_temp.ph(62), pg_temp.mail('rl'), array[pg_temp.d(7)])))::text);
select pg_temp.check((pg_temp.tx('s7')::jsonb) @> '{"ok": false, "error": "too_many_requests"}'::jsonb
    and ((pg_temp.tx('s7')::jsonb)->>'retry_after_seconds')::int between 1 and 61
    and (pg_temp.call('test', 'event_info', '{}')->>'ok')::boolean,
  'S7 more than 120 writes in 10 minutes from one key: too_many_requests with when to try again; reads still answer: ' || pg_temp.tx('s7'));
delete from public.event_web_requests where key_id = pg_temp.fx('key_test') and body_md5 = 'x';
-- S7b HitPay's notices have their own budget: sign-ups that use up theirs never block a payment.
select pg_temp.put('s7b_r', pg_temp.register('live', 's7b', jsonb_build_array(
  pg_temp.person(1, 'Quinn', 'Paying', pg_temp.ph(63), pg_temp.mail('quinn'), array[pg_temp.d(7)])))::text);
select pg_temp.checkout('live', 's7b', array[pg_temp.tok(pg_temp.tx('s7b_r')::jsonb, 1)]);
insert into public.event_web_requests (key_id, request_id, type, is_write, body_md5, outcome, received_at)
select pg_temp.fx('key_live'), gen_random_uuid(), 'register', true, 'x', 'registered', now() - interval '9 minutes' from generate_series(1, 120);
select pg_temp.put('s7b_bot', pg_temp.register('live', 's7b_bot', jsonb_build_array(
  pg_temp.person(1, 'Bot', 'Form', pg_temp.ph(64), pg_temp.mail('bot'), array[pg_temp.d(7)])))::text);
select pg_temp.put('s7b_paid', pg_temp.paid('live', 's7b', array[pg_temp.tok(pg_temp.tx('s7b_r')::jsonb, 1)], 7200)::text);
select pg_temp.check((pg_temp.tx('s7b_bot')::jsonb) @> '{"ok": false, "error": "too_many_requests"}'::jsonb
    and not exists (select 1 from public.event_guests where phone = pg_temp.ph(64))
    and (pg_temp.tx('s7b_paid')::jsonb) @> '{"ok": true, "status": "invoiced"}'::jsonb
    and (select count(*) from pg_temp.vinvoices('s7b') where status = 'paid') = 1,
  'S7b with the sign-up budget used up, a form is refused but HitPay''s payment still goes through and is invoiced: ' || pg_temp.tx('s7b_paid'));
delete from public.event_web_requests where key_id = pg_temp.fx('key_live') and body_md5 = 'x';

-- ═════ F Referral ═════
select pg_temp.put('f1', pg_temp.register('live', 'f1', jsonb_build_array(
  pg_temp.person(1, 'Fern', 'Referred', pg_temp.ph(20), pg_temp.mail('fern'), array[pg_temp.d(7), pg_temp.d(8)]),
  pg_temp.person(2, 'Ken', 'Existing', pg_temp.ph(6), pg_temp.mail('ken'), array[pg_temp.d(8)]),
  pg_temp.person(3, 'Aff', 'Testlink', pg_temp.ph(900), pg_temp.mail('aff'), array[pg_temp.d(7)]),
  pg_temp.person(4, 'Hana', 'Familyphone', pg_temp.ph(3), pg_temp.mail('hana'), array[pg_temp.d(7)]),
  pg_temp.person(5, 'Rosa', 'Attachme', pg_temp.ph(3), pg_temp.mail('rosa2'), array[pg_temp.d(7)])), lower(pg_temp.tx('code_ok')))::text);
create function pg_temp.f1(pos int) returns public.event_registration_people language sql as
$$ select pg_temp.pp(pg_temp.pid(pg_temp.tx('f1')::jsonb, pos)) $$;
select pg_temp.putx('fern', (pg_temp.f1(1)).customer_id);
select pg_temp.check((select (c.referred_by, c.referral_source, c.referral_code_used, c.referred_at is not null)
                        = (pg_temp.fx('aff'), 'affiliate_link', pg_temp.tx('code_ok'), true) from customers c where c.id = pg_temp.fx('fern'))
    and (pg_temp.f1(1)).referral_outcome = 'created'
    and exists (select 1 from referral_signup_events e where e.new_customer_id = pg_temp.fx('fern') and e.outcome = 'created'
                  and e.referrer_customer_id = pg_temp.fx('aff'))
    and exists (select 1 from audit_logs a where a.record_id = pg_temp.fx('fern') and a.action = 'referral_registered'
                  and a.new_data @> jsonb_build_object('source', 'event_website', 'registration_id', pg_temp.bid('REG', 'f1'))),
  'F1 a new person through the link (code typed in lower case): the affiliate''s referral, dated, with an event and the audit row');
select pg_temp.check((pg_temp.f1(2)).referral_outcome = 'already_customer' and (pg_temp.f1(2)).customer_id = pg_temp.fx('c_ken')
    and (select referred_by from customers where id = pg_temp.fx('c_ken')) is null
    and (select count(*) from referral_signup_events e where e.normalized_phone = pg_temp.ph(6) and e.outcome = 'duplicate') = 1,
  'F2 an existing customer through the link keeps their referrer (none): duplicate');
select pg_temp.check((pg_temp.f1(3)).referral_outcome = 'self' and (pg_temp.f1(3)).customer_id = pg_temp.fx('aff'),
  'F3 the affiliate through their own link: self, nothing referred');
select pg_temp.check((pg_temp.f1(4)).referral_outcome = 'held' and (pg_temp.f1(4)).match = 'held',
  'F6 (setup) a family member on a customer''s phone: held, the referral waits');
select pg_temp.put('f4', pg_temp.register('live', 'f4', jsonb_build_array(
  pg_temp.person(1, 'Paula', 'Pausedlink', pg_temp.ph(21), pg_temp.mail('paula'), array[pg_temp.d(7)])), pg_temp.tx('code_off'))::text);
select pg_temp.put('f4b', pg_temp.register('live', 'f4b', jsonb_build_array(
  pg_temp.person(1, 'Una', 'Unknowncode', pg_temp.ph(22), pg_temp.mail('una'), array[pg_temp.d(7)])), 'NOSUCH99')::text);
select pg_temp.check((pg_temp.pp(pg_temp.pid(pg_temp.tx('f4')::jsonb, 1))).referral_outcome = 'link_off'
    and (select referred_by from customers where id = (pg_temp.pp(pg_temp.pid(pg_temp.tx('f4')::jsonb, 1))).customer_id) is null
    and (pg_temp.pp(pg_temp.pid(pg_temp.tx('f4b')::jsonb, 1))).referral_outcome = 'unknown_code'
    and (select referred_by from customers where id = (pg_temp.pp(pg_temp.pid(pg_temp.tx('f4b')::jsonb, 1))).customer_id) is null
    and (pg_temp.tx('f4')::jsonb)->>'status' = 'registered' and (pg_temp.tx('f4b')::jsonb)->>'status' = 'registered',
  'F4 a link switched off, an unknown code: registered, not referred');
insert into referral_signup_events(referral_code, referrer_customer_id, normalized_phone, outcome, created_at)
select pg_temp.tx('code_ok'), pg_temp.fx('aff'), '+61255509999', 'created', now() - interval '30 minutes' from generate_series(1, 20);
select pg_temp.put('f5', pg_temp.register('live', 'f5', jsonb_build_array(
  pg_temp.person(1, 'Lina', 'Limited', pg_temp.ph(23), pg_temp.mail('lina'), array[pg_temp.d(7)])), pg_temp.tx('code_ok'))::text);
select pg_temp.check((pg_temp.pp(pg_temp.pid(pg_temp.tx('f5')::jsonb, 1))).referral_outcome = 'link_limit'
    and (select referred_by from customers where id = (pg_temp.pp(pg_temp.pid(pg_temp.tx('f5')::jsonb, 1))).customer_id) is null
    and exists (select 1 from referral_signup_events where normalized_phone = pg_temp.ph(23) and outcome = 'link_limit'),
  'F5 twenty new people through one link in the last hour: the next registers unreferred (link_limit)');
delete from referral_signup_events where normalized_phone = '+61255509999';
select pg_temp.as_user('staff');
select pg_temp.put('f6', pg_temp.err(format('select public.event_registration_create_customer(%L, %L)', (pg_temp.f1(4)).id, 'Daughter of Rosa, same phone')));
select pg_temp.putx('hana', (pg_temp.f1(4)).customer_id);
select pg_temp.check(pg_temp.tx('f6') = 'ok' and (pg_temp.f1(4)).match = 'staff_created' and (pg_temp.f1(4)).referral_outcome = 'check_waiting'
    and (select (referred_by, referral_source, referral_code_used) is not distinct from (null::uuid, null::text, null::text)
           from customers where id = pg_temp.fx('hana'))
    and exists (select 1 from referral_signup_checks k where k.customer_id = pg_temp.fx('hana') and k.status = 'pending'
                  and k.referrer_customer_id = pg_temp.fx('aff') and k.referral_code = pg_temp.tx('code_ok')
                  and k.phone_shared_with = array[pg_temp.fx('c_phone')])
    and exists (select 1 from referral_signup_events e where e.new_customer_id = pg_temp.fx('hana') and e.outcome = 'phone_shared'
                  and e.referrer_customer_id = pg_temp.fx('aff'))
    and exists (select 1 from audit_logs a where a.record_id = pg_temp.fx('hana') and a.action = 'referral_check_waiting' and a.module = 'affiliate'
                  and a.reason = 'Their phone is on another customer''s record: referred once an Owner or Manager checks them as a different person'
                  and a.new_data @> jsonb_build_object('referrer_customer_id', pg_temp.fx('aff'), 'shares', null,
                                                       'phone_shared_with', jsonb_build_array(pg_temp.fx('c_phone'))))
    and not exists (select 1 from audit_logs a where a.record_id = pg_temp.fx('hana') and a.action = 'referral_registered')
    and (pg_temp.guest((pg_temp.f1(4)).free_guest_id)).customer_id = pg_temp.fx('hana'),
  'F6 staff make a customer of a held person on a phone in use under another name: no referrer yet, a pending check naming the affiliate and sharing with the phone''s customer, the sign-up counted for the link, audited (Q19 = A; the owner, 21 Oct 2026: no commission before the check; section FQ): ' || pg_temp.tx('f6'));
select pg_temp.put('f7_short', pg_temp.err(format('select public.event_registration_attach(%L, %L, %L)', (pg_temp.f1(5)).id, pg_temp.fx('c_phone'), 'ok')));
select pg_temp.put('f7', pg_temp.err(format('select public.event_registration_attach(%L, %L, %L)', (pg_temp.f1(5)).id, pg_temp.fx('c_phone'), 'Same person, asked at the door')));
select pg_temp.check(pg_temp.tx('f7_short') = 'Add a short note on how you confirmed this is the same person.'
    and pg_temp.tx('f7') = 'ok'
    and (pg_temp.f1(5)).match = 'staff_attached' and (pg_temp.f1(5)).customer_id = pg_temp.fx('c_phone')
    and (pg_temp.f1(5)).referral_outcome = 'already_customer'
    and (select referred_by from customers where id = pg_temp.fx('c_phone')) is null
    and (select email from customers where id = pg_temp.fx('c_phone')) = pg_temp.mail('rosa2')
    and exists (select 1 from audit_logs a where a.record_id = (pg_temp.f1(5)).id and a.action = 'event_registration_matched'
                  and a.old_data @> jsonb_build_object('typed_name', 'Rosa Attachme')),
  'F7 staff attach a held person (a note needed): the customer''s empty email filled, their referrer untouched, audited with what was typed');
select pg_temp.check(pg_temp.call('live', 'referral_info', jsonb_build_object('code', lower(pg_temp.tx('code_ok'))))
        = '{"ok": true, "test": false, "status": "ok", "valid": true, "first_name": "Aff", "accepting": true}'::jsonb
    and pg_temp.call('live', 'referral_info', jsonb_build_object('code', pg_temp.tx('code_off')))->>'accepting' = 'false'
    and pg_temp.call('live', 'referral_info', '{"code": "NOSUCH99"}') = '{"ok": true, "test": false, "status": "ok", "valid": false, "first_name": null, "accepting": false}'::jsonb,
  'F8 referral_info: the affiliate''s first name and whether the link takes registrations');

-- ═════ V VIP through HitPay ═════
-- Three people on one payment: Vera through the link (referred), Bob and Cara without.
select pg_temp.put('v1a', pg_temp.register('live', 'v1a', jsonb_build_array(
  pg_temp.person(1, 'Vera', 'Viplink', pg_temp.ph(30), pg_temp.mail('vera'), array[pg_temp.d(7)], true)), pg_temp.tx('code_ok'))::text);
select pg_temp.put('v1b', pg_temp.register('live', 'v1b', jsonb_build_array(
  pg_temp.person(1, 'Bob', 'Vipguest', pg_temp.ph(31), pg_temp.mail('bob'), array[pg_temp.d(7)], true),
  pg_temp.person(2, 'Cara', 'Vipguest', pg_temp.ph(32), pg_temp.mail('cara'), array[pg_temp.d(8)], true)))::text);
select pg_temp.putx('vera', pg_temp.pid(pg_temp.tx('v1a')::jsonb, 1));
select pg_temp.putx('bob', pg_temp.pid(pg_temp.tx('v1b')::jsonb, 1));
select pg_temp.putx('cara', pg_temp.pid(pg_temp.tx('v1b')::jsonb, 2));
select pg_temp.put('tok:vera', pg_temp.tok(pg_temp.tx('v1a')::jsonb, 1));
select pg_temp.put('tok:bob', pg_temp.tok(pg_temp.tx('v1b')::jsonb, 1));
select pg_temp.put('tok:cara', pg_temp.tok(pg_temp.tx('v1b')::jsonb, 2));
-- Bob came on Day 1 before he paid.
select pg_temp.as_user('staff');
select public.event_check_in((pg_temp.pp(pg_temp.fx('bob'))).free_guest_id, pg_temp.d(7), true, 'B1');
select pg_temp.put('person_bob', pg_temp.call('live', 'person', jsonb_build_object('upgrade_token', pg_temp.tx('tok:bob')))::text);
select pg_temp.check((pg_temp.tx('person_bob')::jsonb) = jsonb_build_object('ok', true, 'test', false, 'status', 'ok',
      'person', jsonb_build_object('person_id', pg_temp.fx('bob'), 'upgrade_token', pg_temp.tx('tok:bob'), 'first_name', 'Bob',
                                   'days', jsonb_build_array(pg_temp.d(7)), 'vip', 'none', 'can_upgrade', true, 'reason', null),
      'group', jsonb_build_array(jsonb_build_object('position', 2, 'first_name', 'Cara', 'days', jsonb_build_array(pg_temp.d(8)),
                                   'vip', 'none', 'can_upgrade', true)),
      'vip_price_cents', 7200, 'planning', null, 'planning_open', true)
    and pg_temp.tx('person_bob') !~ pg_temp.tx('tok:cara') and pg_temp.tx('person_bob') !~ pg_temp.fx('cara')::text
    and pg_temp.call('live', 'person', '{"upgrade_token": "vip_aaaaaaaaaaaaaaaaaaaaaaaaaa"}') = '{"ok": true, "test": false, "status": "not_found"}'::jsonb,
  'V0 person: by the VIP link, with the others on the form by first name and days only (never their links or ids); an unknown link is not_found: ' || pg_temp.tx('person_bob'));
select pg_temp.put('v1c', pg_temp.checkout('live', 'v1', array[pg_temp.tx('tok:vera'), pg_temp.tx('tok:bob'), pg_temp.tx('tok:cara')])::text);
select pg_temp.check((pg_temp.tx('v1c')::jsonb) @> jsonb_build_object('ok', true, 'status', 'ok', 'order_id', pg_temp.bid('VIP', 'v1'),
      'unit_price_cents', 7200, 'total_cents', 21600, 'currency', 'SGD')
    and (pg_temp.vorder('v1')).status = 'pending'
    and (pg_temp.tx('v1c')::jsonb)->'people' = jsonb_build_array(jsonb_build_object('person_id', pg_temp.fx('vera'), 'first_name', 'Vera'),
         jsonb_build_object('person_id', pg_temp.fx('bob'), 'first_name', 'Bob'), jsonb_build_object('person_id', pg_temp.fx('cara'), 'first_name', 'Cara'))
    and pg_temp.call('live', 'person', jsonb_build_object('upgrade_token', pg_temp.tx('tok:bob')))->'person'->>'reason' = 'payment_waiting',
  'V1 checkout: three people at S$72 each, S$216, kept pending; their links now say a payment is waiting: ' || pg_temp.tx('v1c'));
select pg_temp.put('v1p', pg_temp.paid('live', 'v1', array[pg_temp.tx('tok:vera'), pg_temp.tx('tok:bob'), pg_temp.tx('tok:cara')], 21600)::text);
select pg_temp.check((pg_temp.tx('v1p')::jsonb) @> '{"ok": true, "test": false, "status": "invoiced", "review_reason": null, "reason": null}'::jsonb
    and (select count(*) from pg_temp.vinvoices('v1') i where i.status = 'paid' and i.total_amount = 72 and i.store_id = pg_temp.fx('van')) = 3
    and (select array_agg(x->>'invoice_no' order by x->>'first_name') from jsonb_array_elements(pg_temp.tx('v1p')::jsonb->'people') x)
        = (select array_agg(i.invoice_no order by c.full_name) from pg_temp.vinvoices('v1') i join customers c on c.id = i.customer_id)
    and not exists (select 1 from jsonb_array_elements(pg_temp.tx('v1p')::jsonb->'people') x where x->>'vip' <> 'paid'),
  'V2 HitPay paid: invoiced, three paid invoices of S$72 at the event''s store, each named in the answer, everyone VIP: ' || pg_temp.tx('v1p'));
select pg_temp.check(
    (select bool_and(i.customer_id = p.customer_id) from event_vip_order_people op
       join event_registration_people p on p.id = op.person_id join invoices i on i.id = op.invoice_id
      where op.order_ref = (pg_temp.vorder('v1')).id)
    and (select bool_and((select jsonb_agg(jsonb_build_array(ii.line_kind::text, coalesce(ii.event_ticket_option_id, ii.voucher_id), ii.quantity,
                                   ii.line_total, coalesce(ii.is_foc, false), ii.foc_reason) order by ii.line_kind::text, ii.unit_price)
                              from invoice_items ii where ii.invoice_id = i.id)
                         = jsonb_build_array(
                             jsonb_build_array('event_ticket', pg_temp.fx('vip'), 1, 72.00, false, null),
                             jsonb_build_array('voucher', pg_temp.fx('save72'), 1, 0.00, true, 'Included with VIP · HT436 Health Seminar ' || pg_temp.tx('sfx')),
                             jsonb_build_array('voucher', pg_temp.fx('three'), 1, 0.00, true, 'Included with VIP · HT436 Health Seminar ' || pg_temp.tx('sfx'))))
           from pg_temp.vinvoices('v1') i)
    and (select bool_and((select event_days from invoice_items ii where ii.invoice_id = i.id and ii.line_kind = 'event_ticket') = array[pg_temp.d(7), pg_temp.d(8)])
           from pg_temp.vinvoices('v1') i),
  'V2 each invoice is the person''s own: the VIP ticket (S$72, both days) and the two vouchers free, "Included with VIP · <event>"');
select pg_temp.check((select bool_and((select count(*) from invoice_payments ip where ip.invoice_id = i.id and ip.amount = 72
                                          and ip.payment_method_id = pg_temp.fx('hitpay')
                                          and ip.payment_reference = (pg_temp.vorder('v1')).hitpay_payment_id) = 1)
                        from pg_temp.vinvoices('v1') i)
    and (select bool_and(i.notes like 'Website VIP · ' || pg_temp.bid('VIP', 'v1') || ' · HitPay % of 3') from pg_temp.vinvoices('v1') i),
  'V2 one HitPay payment is a S$72 payment on each invoice, all with the payment''s reference; the notes name the order');
select pg_temp.check((select count(*) from customer_reward_vouchers v join pg_temp.vinvoices('v1') i on i.customer_id = v.customer_id
                       where v.status = 'held' and v.source_type = 'invoice_voucher_sale' and v.voucher_id in (pg_temp.fx('save72'), pg_temp.fx('three'))) = 6
    and (select count(distinct v.customer_id) from customer_reward_vouchers v join pg_temp.vinvoices('v1') i on i.customer_id = v.customer_id
          where v.status = 'held') = 3,
  'V2 the S$72 voucher and the 3-in-1 are on each VIP''s own account (six vouchers, three customers)');
select pg_temp.check((select jsonb_agg(jsonb_build_array(c.tier::text, c.referrer_customer_id, c.commission_amount) order by c.tier::text)
                        from commissions c join pg_temp.vinvoices('v1') i on i.id = c.invoice_id)
                     = jsonb_build_array(jsonb_build_array('tier1', pg_temp.fx('aff'), 10.80), jsonb_build_array('tier2', pg_temp.fx('upline'), 0.54)),
  'V2 commission on Vera''s VIP alone, by the app''s engine: 15% of S$72 (S$10.80) to the affiliate, 5% of that (S$0.54) to theirs; the free vouchers earn none, Bob and Cara none');
select pg_temp.check((pg_temp.guest((pg_temp.pp(pg_temp.fx('bob'))).free_guest_id)).status = 'cancelled'
    and (pg_temp.guest((pg_temp.pp(pg_temp.fx('bob'))).free_guest_id)).cancelled_reason like 'Upgraded to VIP · %'
    and (pg_temp.guest((pg_temp.pp(pg_temp.fx('bob'))).vip_guest_id)).status = 'registered'
    and (pg_temp.guest((pg_temp.pp(pg_temp.fx('bob'))).vip_guest_id)).ticket_option_id = pg_temp.fx('vip')
    and (select array_agg(day order by day) from event_guest_days where guest_id = (pg_temp.pp(pg_temp.fx('cara'))).vip_guest_id) = array[pg_temp.d(7), pg_temp.d(8)]
    and (select (attended_at is not null, check_in_code) from event_guest_days where guest_id = (pg_temp.pp(pg_temp.fx('bob'))).vip_guest_id and day = pg_temp.d(7)) = (true, 'B1'::text)
    and (select count(*) from event_guests where event_id = pg_temp.fx('ev') and status = 'registered' and phone = pg_temp.ph(31)) = 1,
  'V2 each VIP is on the list once: the VIP record on both days with Bob''s Day 1 check-in, the free record parked');
select pg_temp.put('v3', pg_temp.paid('live', 'v1', array[pg_temp.tx('tok:vera'), pg_temp.tx('tok:bob'), pg_temp.tx('tok:cara')], 21600)::text);
select pg_temp.check(pg_temp.tx('v3')::jsonb = pg_temp.tx('v1p')::jsonb and (select count(*) from pg_temp.vinvoices('v1')) = 3
    and (pg_temp.checkout('live', 'v1x', array[pg_temp.tx('tok:bob')])) @> jsonb_build_object('status', 'refused', 'reason', 'already_vip', 'person_ids', jsonb_build_array(pg_temp.fx('bob'))),
  'V3 the payment again (webhook and /vip/done): the same answer, nothing twice; Bob cannot pay again (already_vip)');

-- V4 an amount that is not the price.
select pg_temp.put('v4r', pg_temp.register('live', 'v4', jsonb_build_array(
  pg_temp.person(1, 'Dina', 'Amount', pg_temp.ph(33), pg_temp.mail('dina'), array[pg_temp.d(7)]),
  pg_temp.person(2, 'Eli', 'Waiting', pg_temp.ph(34), pg_temp.mail('eli'), array[pg_temp.d(7)]),
  pg_temp.person(3, 'Fay', 'Offsale', pg_temp.ph(35), pg_temp.mail('fay'), array[pg_temp.d(8)]),
  pg_temp.person(4, 'Gus', 'Recordonly', pg_temp.ph(36), pg_temp.mail('gus'), array[pg_temp.d(8)]),
  pg_temp.person(5, 'Hal', 'Late', pg_temp.ph(37), pg_temp.mail('hal'), array[pg_temp.d(8)])))::text);
create function pg_temp.v4tok(pos int) returns text language sql as $$ select pg_temp.tok(pg_temp.tx('v4r')::jsonb, pos) $$;
select pg_temp.checkout('live', 'v4', array[pg_temp.v4tok(1)]);
select pg_temp.put('v4', pg_temp.paid('live', 'v4', array[pg_temp.v4tok(1)], 7000)::text);
select pg_temp.check((pg_temp.tx('v4')::jsonb) @> '{"status": "needs_review", "review_reason": "HitPay charged S$70.00, but 1 × VIP costs S$72.00"}'::jsonb
    and not exists (select 1 from pg_temp.vinvoices('v4')),
  'V4 HitPay charged other than the price: waits for a Manager, nothing invoiced: ' || pg_temp.tx('v4'));
-- V6 a payment waiting.
select pg_temp.checkout('live', 'v6a', array[pg_temp.v4tok(2)]);
select pg_temp.put('v6b', pg_temp.checkout('live', 'v6b', array[pg_temp.v4tok(2)])::text);
select pg_temp.put('v6a2', pg_temp.checkout('live', 'v6a', array[pg_temp.v4tok(2)])::text);
select pg_temp.put('v6a3', pg_temp.checkout('live', 'v6a', array[pg_temp.v4tok(3)])::text);
select pg_temp.check((pg_temp.tx('v6b')::jsonb) @> jsonb_build_object('status', 'refused', 'reason', 'payment_waiting')
    and (pg_temp.tx('v6a2')::jsonb) @> '{"status": "ok"}'::jsonb
    and (pg_temp.tx('v6a3')::jsonb) @> '{"status": "refused", "reason": "id_reused"}'::jsonb
    and not exists (select 1 from event_vip_orders where order_id = pg_temp.bid('VIP', 'v6b')),
  'V6 a second checkout while one is open: payment_waiting (nothing kept); the same order again: ok; its id with other people: id_reused');
update event_vip_orders set expires_at = now() - interval '1 minute' where order_id = pg_temp.bid('VIP', 'v6a');
select pg_temp.check(pg_temp.checkout('live', 'v6c', array[pg_temp.v4tok(2)]) @> '{"status": "ok"}'::jsonb,
  'V6 once the open checkout expires (70 minutes), the person can pay again');
-- V7 VIP taken off sale after the payment: still invoiced (415's rule).
select pg_temp.checkout('live', 'v7', array[pg_temp.v4tok(3)]);
update event_ticket_options set is_active = false where id = pg_temp.fx('vip');
select pg_temp.put('v7', pg_temp.paid('live', 'v7', array[pg_temp.v4tok(3)], 7200)::text);
select pg_temp.put('v7x', pg_temp.checkout('live', 'v7x', array[pg_temp.v4tok(4)])::text);
select pg_temp.check((pg_temp.tx('v7')::jsonb)->>'status' = 'invoiced' and (select count(*) from pg_temp.vinvoices('v7') where status = 'paid') = 1
    and (pg_temp.tx('v7x')::jsonb) @> '{"status": "refused", "reason": "vip_off_sale"}'::jsonb,
  'V7 VIP taken off sale after the payment: still invoiced; a new checkout is refused (vip_off_sale): ' || pg_temp.tx('v7'));
select pg_temp.as_user('owner');
select pg_temp.check(pg_temp.err(format('select public.create_invoice_with_details(%L, %L, %L, %L)', pg_temp.fx('van'), pg_temp.fx('c_exact'),
         jsonb_build_array(jsonb_build_object('kind', 'event_ticket', 'event_ticket_option_id', pg_temp.fx('vip'), 'quantity', 1,
           'attendees', jsonb_build_array(jsonb_build_object('name', 'Counter Person')))), jsonb_build_object('business_date', public.sg_today())))
         like '"VIP" tickets for % are not on sale',
  'V7 the patch lets only the paid order through: a counter sale of the off-sale VIP ticket is still refused');
update event_ticket_options set is_active = true where id = pg_temp.fx('vip');
-- V8 Record only: recorded, then a Manager creates the invoices.
update event_web_settings set mode = 'record_only' where event_id = pg_temp.fx('ev');
select pg_temp.checkout('live', 'v8', array[pg_temp.v4tok(4)]);
select pg_temp.put('v8', pg_temp.paid('live', 'v8', array[pg_temp.v4tok(4)], 7200)::text);
update event_web_settings set mode = 'live' where event_id = pg_temp.fx('ev');
select pg_temp.as_user('staff');
select pg_temp.put('v8_staff', pg_temp.errcode(format('select public.event_vip_order_invoice(%L)', (pg_temp.vorder('v8')).id)));
select pg_temp.as_user('manager');
select pg_temp.put('v8_mgr', public.event_vip_order_invoice((pg_temp.vorder('v8')).id)::text);
select pg_temp.check((pg_temp.tx('v8')::jsonb)->>'status' = 'recorded' and pg_temp.tx('v8_staff') = '42501'
    and (pg_temp.tx('v8_mgr')::jsonb)->>'status' = 'invoiced' and (select count(*) from pg_temp.vinvoices('v8') where status = 'paid') = 1
    and exists (select 1 from audit_logs a where a.record_id = (pg_temp.vorder('v8')).id and a.action = 'event_vip_order_invoiced'
                  and a.changed_by = pg_temp.fx('manager')),
  'V8 Record only: the payment is recorded; staff cannot create its invoices, a Manager can (audited)');
-- V9 the times.
select pg_temp.checkout('live', 'v9', array[pg_temp.v4tok(5)], true, now() - interval '3 hours');
select pg_temp.put('v9', pg_temp.paid('live', 'v9', array[pg_temp.v4tok(5)], 7200)::text);
select pg_temp.as_user('manager');
select pg_temp.put('v9_mgr', public.event_vip_order_invoice((pg_temp.vorder('v9')).id)::text);
select pg_temp.check((pg_temp.tx('v9')::jsonb) @> '{"status": "needs_review", "review_reason": "It was paid more than 2 hours after the checkout opened. Check the payment in HitPay before creating its invoices"}'::jsonb
    and (pg_temp.tx('v9_mgr')::jsonb)->>'status' = 'invoiced',
  'V9 paid more than 2 hours after the checkout opened: waits; a Manager who checked creates the invoices: ' || pg_temp.tx('v9'));
-- V10 HitPay's sandbox with the live key.
select pg_temp.put('v10r', pg_temp.register('live', 'v10', jsonb_build_array(
  pg_temp.person(1, 'Ivy', 'Sandbox', pg_temp.ph(38), pg_temp.mail('ivy'), array[pg_temp.d(7)])))::text);
select pg_temp.put('v10c', pg_temp.checkout('live', 'v10', array[pg_temp.tok(pg_temp.tx('v10r')::jsonb, 1)], false)::text);
select pg_temp.put('v10p', pg_temp.paid('live', 'v10', array[pg_temp.tok(pg_temp.tx('v10r')::jsonb, 1)], 7200, false)::text);
select pg_temp.check((pg_temp.tx('v10c')::jsonb) @> '{"status": "refused", "reason": "livemode_mismatch"}'::jsonb
    and (pg_temp.tx('v10p')::jsonb) @> '{"status": "refused", "review_reason": "A HitPay test payment", "reason": "livemode_mismatch"}'::jsonb
    and not exists (select 1 from pg_temp.vinvoices('v10')),
  'V10 the live key refuses HitPay''s sandbox, at checkout and at payment (nothing invoiced)');

-- V5 a held person's payment waits, and is invoiced once staff match them.
select pg_temp.put('tok:gina', (pg_temp.r2(4)).upgrade_token);
select pg_temp.checkout('live', 'v5', array[pg_temp.tx('tok:gina')]);
select pg_temp.put('v5', pg_temp.paid('live', 'v5', array[pg_temp.tx('tok:gina')], 7200)::text);
select pg_temp.check((pg_temp.tx('v5')::jsonb) @> '{"status": "needs_review", "review_reason": "Person 1 on this order is still to be matched to a customer (Guests, To match). It is invoiced once they are"}'::jsonb
    and (pg_temp.vorder('v5')).waiting_for_match,
  'V5 a held person''s HitPay payment waits for staff to match them: ' || pg_temp.tx('v5'));
select pg_temp.as_user('staff');
select pg_temp.put('v5_create', public.event_registration_create_customer((pg_temp.r2(4)).id, 'A different Gina')::text);
select pg_temp.check((pg_temp.vorder('v5')).status = 'invoiced'
    and (pg_temp.tx('v5_create')::jsonb)->'vip_orders'->0 @> jsonb_build_object('order_id', pg_temp.bid('VIP', 'v5'), 'status', 'invoiced')
    and (select customer_id from pg_temp.vinvoices('v5')) = (pg_temp.r2(4)).customer_id
    and (select count(*) from customer_reward_vouchers v where v.customer_id = (pg_temp.r2(4)).customer_id and v.status = 'held') = 2,
  'V5 staff make her a customer: the waiting payment is invoiced at once, to her, with her vouchers');

-- V11 the test key changes nothing.
select pg_temp.put('cust_before', (select count(*) from customers)::text);
select pg_temp.put('inv_before', (select count(*) from invoices)::text);
select pg_temp.put('guests_before', (select count(*) from event_guests)::text);
select pg_temp.put('vouch_before', (select count(*) from customer_reward_vouchers)::text);
select pg_temp.put('t1', pg_temp.register('test', 't1', jsonb_build_array(
  pg_temp.person(1, 'Tess', 'Testing', pg_temp.ph(50), pg_temp.mail('tess'), array[pg_temp.d(7)]),
  pg_temp.person(2, 'Mei Ling', 'Tan', pg_temp.ph(1), pg_temp.mail('meiling'), array[pg_temp.d(7)])), pg_temp.tx('code_ok'))::text);
select pg_temp.put('t1c', pg_temp.checkout('test', 't1', array[pg_temp.tok(pg_temp.tx('t1')::jsonb, 1), pg_temp.tok(pg_temp.tx('t1')::jsonb, 2)], false)::text);
select pg_temp.put('t1p', pg_temp.paid('test', 't1', array[pg_temp.tok(pg_temp.tx('t1')::jsonb, 1), pg_temp.tok(pg_temp.tx('t1')::jsonb, 2)], 14400, false)::text);
select pg_temp.put('t1t', pg_temp.transfer('test', 't1t', array[pg_temp.tok(pg_temp.tx('t1')::jsonb, 1)], 'paynow', 7200, public.sg_today())::text);
select pg_temp.check((pg_temp.tx('t1')::jsonb) @> '{"ok": true, "test": true, "status": "registered"}'::jsonb
    and (pg_temp.tx('t1c')::jsonb) @> '{"test": true, "status": "ok", "total_cents": 14400}'::jsonb
    and (pg_temp.tx('t1p')::jsonb) @> '{"test": true, "status": "test", "test_note": "A live key would have made 2 invoice(s) of S$72.00 (VIP ticket, with 2 voucher(s) free), paid by HitPay (online)."}'::jsonb
    and (pg_temp.tx('t1t')::jsonb) @> '{"test": true, "status": "test"}'::jsonb
    and (select count(*) from customers)::text = pg_temp.tx('cust_before') and (select count(*) from invoices)::text = pg_temp.tx('inv_before')
    and (select count(*) from event_guests)::text = pg_temp.tx('guests_before')
    and (select count(*) from customer_reward_vouchers)::text = pg_temp.tx('vouch_before')
    and (pg_temp.pp(pg_temp.pid(pg_temp.tx('t1')::jsonb, 2))).test_outcome = '{"match": "exact", "hold_reason": null, "referral": "already_customer"}'::jsonb
    and (pg_temp.pp(pg_temp.pid(pg_temp.tx('t1')::jsonb, 1))).test_outcome = '{"match": "new_customer", "hold_reason": null, "referral": "created"}'::jsonb
    and (select referred_by from customers where id = pg_temp.fx('c_exact')) is null,
  'V11 the test key: answers marked test, no customer, guest, invoice or voucher; what a live key would have done is kept: ' || pg_temp.tx('t1p'));
select pg_temp.put('v10t', pg_temp.paid('test', 't2', array[pg_temp.tok(pg_temp.tx('t1')::jsonb, 1)], 7200, true)::text);
select pg_temp.put('v10t2', pg_temp.checkout('test', 't3', array[pg_temp.tok(pg_temp.tx('t1')::jsonb, 2)], true)::text);
select pg_temp.put('v10t3', pg_temp.checkout('test', 't4', array[pg_temp.tx('tok:bob')], false)::text);
select pg_temp.check((pg_temp.tx('v10t')::jsonb) @> '{"test": true, "status": "needs_review", "review_reason": "A real payment came through the website''s TEST key: refund it in HitPay, or have an Owner switch the website to its live key"}'::jsonb
    and (pg_temp.tx('v10t2')::jsonb) @> '{"status": "refused", "reason": "livemode_mismatch"}'::jsonb
    and (pg_temp.tx('v10t3')::jsonb) @> '{"status": "refused", "reason": "person_not_found"}'::jsonb,
  'V10 a real payment through the test key is kept for a Manager; the test key refuses a live checkout and live people');

-- ═════ T PayNow and bank transfers ═════
select pg_temp.put('t_r', pg_temp.register('live', 'tr', jsonb_build_array(
  pg_temp.person(1, 'Jo', 'Paynow', pg_temp.ph(39), pg_temp.mail('jo'), array[pg_temp.d(7)]),
  pg_temp.person(2, 'Kit', 'Bank', pg_temp.ph(41), pg_temp.mail('kit'), array[pg_temp.d(7)])))::text);
create function pg_temp.ttok(pos int) returns text language sql as $$ select pg_temp.tok(pg_temp.tx('t_r')::jsonb, pos) $$;
select pg_temp.put('tt1', pg_temp.transfer('live', 'tp1', array[pg_temp.ttok(1)], 'paynow', 7200, public.sg_today(), pg_temp.ph(39), 'PN-777')::text);
select pg_temp.put('tt1b', pg_temp.transfer('live', 'tp1', array[pg_temp.ttok(1)], 'paynow', 7200, public.sg_today(), pg_temp.ph(39), 'PN-777')::text);
select pg_temp.check((pg_temp.tx('tt1')::jsonb) @> '{"status": "recorded", "review_reason": null}'::jsonb
    and not exists (select 1 from pg_temp.vinvoices('tp1'))
    and pg_temp.call('live', 'person', jsonb_build_object('upgrade_token', pg_temp.ttok(1)))->'person'->>'vip' = 'pending'
    and pg_temp.tx('tt1b') = pg_temp.tx('tt1'),
  'T1 a PayNow transfer that adds up is recorded, never invoiced by itself; the person''s VIP is pending; sent again, the same answer');
select pg_temp.put('tt2', pg_temp.transfer('live', 'tp2', array[pg_temp.ttok(2)], 'bank', 7000, public.sg_today() + 1)::text);
select pg_temp.put('tt2b', pg_temp.transfer('live', 'tp2b', array[pg_temp.ttok(1)], 'paynow', 7200, public.sg_today() - 61, pg_temp.ph(39))::text);
select pg_temp.put('tt2c', pg_temp.transfer('live', 'tp2c', array[(pg_temp.r2(5)).upgrade_token], 'paynow', 7200, public.sg_today())::text);
select pg_temp.check((pg_temp.tx('tt2')::jsonb) @> jsonb_build_object('status', 'needs_review', 'review_reason',
        format('S$70.00 was paid, but 1 × VIP costs S$72.00. The date paid (%s) is after today', to_char(public.sg_today() + 1, 'DD Mon YYYY')))
    and (pg_temp.tx('tt2b')::jsonb)->>'review_reason' = format('The date paid (%s) is more than 60 days before the order. Possibly the same as %s. Person 1 on this order has another VIP payment waiting (%s)',
          to_char(public.sg_today() - 61, 'DD Mon YYYY'), pg_temp.bid('VIP', 'tp1'), pg_temp.bid('VIP', 'tp1'))
    and (pg_temp.tx('tt2c')::jsonb)->>'review_reason' = 'Person 1 on this order is still to be matched to a customer (Guests, To match)',
  'T2 every reason at once: the amount, a date after today or 60 days back, a possible repeat, a payment waiting, a person to match');
select pg_temp.as_user('admin');
select pg_temp.put('tt3', public.event_vip_order_invoice((pg_temp.vorder('tp1')).id)::text);
select pg_temp.check((pg_temp.tx('tt3')::jsonb)->>'status' = 'invoiced'
    and (select (ip.payment_method_id, ip.payment_reference, ip.amount) = (pg_temp.fx('paynow'), 'PN-777', 72::numeric)
           from invoice_payments ip join pg_temp.vinvoices('tp1') i on i.id = ip.invoice_id)
    and (select i.notes from pg_temp.vinvoices('tp1') i) = 'Website VIP · ' || pg_temp.bid('VIP', 'tp1') || ' · PayNow ref PN-777 · 1 of 1'
    and (select i.business_date from pg_temp.vinvoices('tp1') i) = public.sg_today(),
  'T3 an Admin confirms the money arrived: invoiced, paid by PayNow with the buyer''s reference, dated the day paid: ' || pg_temp.tx('tt3'));
select pg_temp.as_user('manager');
select pg_temp.put('t4_short', pg_temp.err(format('select public.event_vip_order_dismiss(%L, %L, true)', (pg_temp.vorder('tp2')).id, 'no')));
select pg_temp.put('t4_ref', pg_temp.err(format('select public.event_vip_order_dismiss(%L, %L, true)', (pg_temp.vorder('tp2')).id, 'Refunded outside the app: x')));
select pg_temp.put('t4_hp', pg_temp.err(format('select public.event_vip_order_dismiss(%L, %L, true)', (pg_temp.vorder('v4')).id, 'Never paid')));
select pg_temp.put('t4', pg_temp.err(format('select public.event_vip_order_dismiss(%L, %L, true)', (pg_temp.vorder('tp2')).id, 'Typed the wrong amount, sent again')));
select pg_temp.check(pg_temp.tx('t4_short') = 'Give a reason (at least 3 characters)' and pg_temp.tx('t4_ref') = 'Use Close as refunded for a refund'
    and pg_temp.tx('t4_hp') = 'A HitPay payment took money: create its invoices, or close it as refunded.' and pg_temp.tx('t4') = 'ok'
    and ((pg_temp.vorder('tp2')).status, (pg_temp.vorder('tp2')).review_reason) = ('dismissed'::text, 'Typed the wrong amount, sent again'::text),
  'T4 a transfer is dismissed with a reason (not a refund''s; a HitPay payment never)');
select pg_temp.put('t4r', pg_temp.err(format('select public.event_vip_order_dismiss(%L, null, false)', (pg_temp.vorder('tp2')).id)));
select pg_temp.check(pg_temp.tx('t4r') = 'ok' and (pg_temp.vorder('tp2')).status = 'needs_review'
    and (pg_temp.vorder('tp2')).review_reason like 'S$70.00 was paid%',
  'T4 restored, it waits again with its reasons');
select pg_temp.as_user('admin');
select pg_temp.put('t5_admin', pg_temp.errcode(format('select public.event_vip_order_close_refunded(%L, %L, true)', (pg_temp.vorder('v4')).id, 'Refunded in HitPay')));
select pg_temp.as_user('manager');
select pg_temp.put('t5', pg_temp.err(format('select public.event_vip_order_close_refunded(%L, %L, true)', (pg_temp.vorder('v4')).id, 'Refunded in HitPay on 21 Oct')));
select pg_temp.check(pg_temp.tx('t5_admin') = '42501' and pg_temp.tx('t5') = 'ok'
    and ((pg_temp.vorder('v4')).status, (pg_temp.vorder('v4')).review_reason) = ('dismissed'::text, 'Refunded outside the app: Refunded in HitPay on 21 Oct'::text),
  'T5 an Owner or Manager (not an Admin) closes a payment refunded outside the app, with the reason');
select pg_temp.put('t5r', pg_temp.err(format('select public.event_vip_order_close_refunded(%L, null, false)', (pg_temp.vorder('v4')).id)));
select pg_temp.check(pg_temp.tx('t5r') = 'ok' and ((pg_temp.vorder('v4')).status, (pg_temp.vorder('v4')).review_reason)
                       = ('needs_review'::text, 'HitPay charged S$70.00, but 1 × VIP costs S$72.00'::text),
  'T5 reopened, it is as it was before the close');
-- T6 the buyer typed S$72 for two: Create invoices refuses (and says what to do) until an Owner or Manager enters what arrived.
select pg_temp.put('t6_r', pg_temp.register('live', 't6', jsonb_build_array(
  pg_temp.person(1, 'Pia', 'Twopeople', pg_temp.ph(42), pg_temp.mail('pia'), array[pg_temp.d(7)]),
  pg_temp.person(2, 'Raj', 'Twopeople', pg_temp.ph(43), pg_temp.mail('raj'), array[pg_temp.d(8)])))::text);
select pg_temp.put('t6', pg_temp.transfer('live', 'tp6', array[pg_temp.tok(pg_temp.tx('t6_r')::jsonb, 1), pg_temp.tok(pg_temp.tx('t6_r')::jsonb, 2)],
  'paynow', 7200, public.sg_today(), pg_temp.ph(42), 'PN-606')::text);
select pg_temp.as_user('manager');
select pg_temp.put('t6_plain', public.event_vip_order_invoice((pg_temp.vorder('tp6')).id)::text);
select pg_temp.as_user('admin');
select pg_temp.put('t6_admin', pg_temp.errcode(format('select public.event_vip_order_invoice(%L, 14400)', (pg_temp.vorder('tp6')).id)));
select pg_temp.put('t6_hp', pg_temp.err(format('select public.event_vip_order_invoice(%L, 7200)', (pg_temp.vorder('v4')).id)));
select pg_temp.as_user('manager');
select pg_temp.put('t6_ok', public.event_vip_order_invoice((pg_temp.vorder('tp6')).id, 14400)::text);
select pg_temp.check((pg_temp.tx('t6')::jsonb)->>'review_reason' = 'S$72.00 was paid, but 2 × VIP costs S$144.00'
    and (pg_temp.tx('t6_plain')::jsonb)->>'status' = 'needs_review'
    and (pg_temp.tx('t6_plain')::jsonb)->>'review_reason' = 'The invoices would be S$144.00 but S$72.00 was paid, so nothing was invoiced. If the buyer typed the amount wrong, enter what arrived when you create the invoices; if what arrived is not 2 × S$72.00, dismiss this order and send the VIP link again for the people actually paid for'
    and pg_temp.tx('t6_admin') = '42501'
    and pg_temp.tx('t6_hp') = 'Only a PayNow or bank transfer''s amount is entered here: HitPay''s is what HitPay charged'
    and (pg_temp.vorder('v4')).amount_paid_cents = 7000
    and (pg_temp.tx('t6_ok')::jsonb)->>'status' = 'invoiced' and (select count(*) from pg_temp.vinvoices('tp6') where status = 'paid') = 2
    and exists (select 1 from audit_logs a where a.record_id = (pg_temp.vorder('tp6')).id and a.action = 'event_vip_order_amount_corrected'
                  and a.old_data = '{"amount_paid_cents": 7200}'::jsonb and a.new_data @> '{"amount_paid_cents": 14400}'::jsonb
                  and a.changed_by = pg_temp.fx('manager')),
  'T6 S$72 typed for two: Create invoices refuses and says what to do; an Owner or Manager (not an Admin) enters the S$144 that arrived (audited); never HitPay''s amount: ' || pg_temp.tx('t6_plain'));
-- T7 the same transfer sent again by the website (a new request id, another submitted_at): the same answer; another amount under its id: id_reused.
create function pg_temp.transfer_again(cents int, extra interval) returns jsonb language sql as
$$ select pg_temp.call('live', 'vip_transfer', jsonb_build_object('order', jsonb_build_object(
     'order_id', pg_temp.bid('VIP', 'tp1'), 'upgrade_tokens', to_jsonb(array[pg_temp.ttok(1)]),
     'payer', jsonb_build_object('name', 'Payer tp1', 'email', pg_temp.mail('payer-tp1'), 'phone', pg_temp.ph(39)),
     'method', 'paynow', 'reference', 'PN-777', 'paid_on', public.sg_today(), 'amount_cents', cents,
     'submitted_at', now() + extra))) $$;
select pg_temp.put('t7a', pg_temp.transfer_again(7200, interval '1 second')::text);
select pg_temp.put('t7b', pg_temp.transfer_again(7000, interval '2 seconds')::text);
select pg_temp.check((pg_temp.tx('t7a')::jsonb) = public.event_web_order_answer((pg_temp.vorder('tp1')).id)
    and (pg_temp.tx('t7a')::jsonb)->>'status' = 'invoiced'
    and (pg_temp.tx('t7b')::jsonb) @> '{"status": "refused", "reason": "id_reused"}'::jsonb,
  'T7 a transfer sent again a second later (same people, amount, reference and day): the first answer; another amount under its id: id_reused: ' || pg_temp.tx('t7a'));
-- T8 a Manager of another of the event's stores cannot create, dismiss or close its VIP orders, nor match its registrations (415's rule).
insert into public.event_stores (event_id, store_id) values (pg_temp.fx('ev'), pg_temp.fx('shop'));
select pg_temp.as_user('manager2');
select pg_temp.put('t8_run', public.event_can_run(pg_temp.fx('ev'))::text);
select pg_temp.put('t8_inv', pg_temp.errcode(format('select public.event_vip_order_invoice(%L)', (pg_temp.vorder('tp2')).id)));
select pg_temp.put('t8_dis', pg_temp.err(format('select public.event_vip_order_dismiss(%L, %L, true)', (pg_temp.vorder('tp2')).id, 'Not ours')));
select pg_temp.put('t8_close', pg_temp.errcode(format('select public.event_vip_order_close_refunded(%L, %L, true)', (pg_temp.vorder('v4')).id, 'Refunded in HitPay')));
select pg_temp.put('t8_attach', pg_temp.errcode(format('select public.event_registration_attach(%L, %L, %L)', (pg_temp.r2(7)).id, pg_temp.fx('c_phone'), 'Asked at the door')));
select pg_temp.put('t8_create', pg_temp.errcode(format('select public.event_registration_create_customer(%L, %L)', (pg_temp.r2(7)).id, 'Another person')));
select pg_temp.put('t8_regclose', pg_temp.errcode(format('select public.event_registration_close(%L, %L)', (pg_temp.r2(7)).id, 'A test form')));
delete from public.event_stores where event_id = pg_temp.fx('ev') and store_id = pg_temp.fx('shop');
select pg_temp.check(pg_temp.tx('t8_run') = 'true'
    and pg_temp.tx('t8_inv') = '42501' and pg_temp.tx('t8_dis') = 'You do not have access to this event''s store'
    and pg_temp.tx('t8_close') = '42501' and pg_temp.tx('t8_attach') = '42501' and pg_temp.tx('t8_create') = '42501'
    and pg_temp.tx('t8_regclose') = '42501'
    and (pg_temp.vorder('tp2')).status = 'needs_review' and (pg_temp.vorder('v4')).status = 'needs_review'
    and (pg_temp.r2(7)).match = 'held',
  'T8 a Manager who runs the event at another store cannot create invoices, dismiss, close as refunded, or match, create or close a registration');

-- ═════ X Refunds ═════
select pg_temp.putx('inv_vera', (select i.id from pg_temp.vinvoices('v1') i where i.customer_id = (pg_temp.pp(pg_temp.fx('vera'))).customer_id));
select pg_temp.putx('inv_bob', (select i.id from pg_temp.vinvoices('v1') i where i.customer_id = (pg_temp.pp(pg_temp.fx('bob'))).customer_id));
select pg_temp.as_user('staff');
select public.event_check_in((pg_temp.pp(pg_temp.fx('bob'))).vip_guest_id, pg_temp.d(8), true, 'B2');
select pg_temp.put('x4', pg_temp.err(format('select public.event_set_guest_cancelled(%L, false, null)', (pg_temp.pp(pg_temp.fx('cara'))).free_guest_id)));
select pg_temp.check(pg_temp.tx('x4') = 'Cara Vipguest is a VIP guest: their VIP record is on the list',
  'X4 a VIP''s parked free record cannot be restored by hand: ' || pg_temp.tx('x4'));
select pg_temp.as_user('owner');
select public.cancel_invoice_recorded(pg_temp.fx('inv_vera'), 'Asked for a refund', gen_random_uuid());
select public.cancel_invoice_recorded(pg_temp.fx('inv_bob'), 'Cannot come', gen_random_uuid());
select pg_temp.put('x1_person', pg_temp.call('live', 'person', jsonb_build_object('upgrade_token', pg_temp.tx('tok:vera')))::text);
select pg_temp.check((select count(*) from customer_reward_vouchers v join invoice_benefit_values b on b.reward_voucher_id = v.id
                       where b.invoice_id = pg_temp.fx('inv_vera') and v.status = 'revoked') = 2
    and (pg_temp.guest((pg_temp.pp(pg_temp.fx('vera'))).vip_guest_id)).status = 'cancelled'
    and (pg_temp.guest((pg_temp.pp(pg_temp.fx('vera'))).free_guest_id)).status = 'registered'
    and not exists (select 1 from commissions c where c.invoice_id = pg_temp.fx('inv_vera') and c.status::text in ('earned', 'blocked'))
    and (pg_temp.tx('x1_person')::jsonb)->'person' @> '{"vip": "refunded", "can_upgrade": true, "reason": null}'::jsonb,
  'X1 a VIP invoice cancelled: its vouchers taken back, the VIP record cancelled, the free one back, the commission reversed; VIP can be bought again');
select pg_temp.check((select jsonb_agg(jsonb_build_array(day, attended_at is not null, check_in_code) order by day) from event_guest_days
                       where guest_id = (pg_temp.pp(pg_temp.fx('bob'))).free_guest_id)
                     = jsonb_build_array(jsonb_build_array(pg_temp.d(7), true, 'B1'), jsonb_build_array(pg_temp.d(8), true, 'B2')),
  'X1 the free record comes back with the days they came (Day 2 as VIP added to it)');
select public.reopen_invoice(pg_temp.fx('inv_bob'), 'Can come after all', gen_random_uuid());
select pg_temp.check((pg_temp.guest((pg_temp.pp(pg_temp.fx('bob'))).vip_guest_id)).status = 'registered'
    and (pg_temp.guest((pg_temp.pp(pg_temp.fx('bob'))).free_guest_id)).status = 'cancelled'
    and (pg_temp.guest((pg_temp.pp(pg_temp.fx('bob'))).free_guest_id)).cancelled_reason
        = 'Upgraded to VIP · ' || (select invoice_no from invoices where id = pg_temp.fx('inv_bob')),
  'X2 the invoice reopened: the VIP record is back and the free one parked again');
select pg_temp.put('x3', pg_temp.call('live', 'vip_refund', jsonb_build_object('refund', jsonb_build_object('order_id', pg_temp.bid('VIP', 'v1'),
  'payment_request_id', (pg_temp.vorder('v1')).hitpay_payment_request_id, 'payment_id', null, 'refunded_cents_total', 7200,
  'refunded_at', now(), 'livemode', true)))::text);
select pg_temp.put('x3b', pg_temp.call('live', 'vip_refund', jsonb_build_object('refund', jsonb_build_object('order_id', pg_temp.bid('VIP', 'v1'),
  'payment_request_id', (pg_temp.vorder('v1')).hitpay_payment_request_id, 'payment_id', null, 'refunded_cents_total', 100,
  'refunded_at', now(), 'livemode', true)))::text);
select pg_temp.put('x3c', pg_temp.call('live', 'vip_refund', jsonb_build_object('refund', jsonb_build_object('order_id', pg_temp.bid('VIP', 'v1'),
  'payment_request_id', '00000000-0000-4000-a000-000000000000', 'payment_id', null, 'refunded_cents_total', 7200,
  'refunded_at', now(), 'livemode', true)))::text);
select pg_temp.as_user('manager');
select pg_temp.check((pg_temp.tx('x3')::jsonb) = jsonb_build_object('ok', true, 'test', false, 'status', 'noted', 'order_id', pg_temp.bid('VIP', 'v1'), 'refunded_cents_total', 7200)
    and (pg_temp.tx('x3b')::jsonb)->>'refunded_cents_total' = '7200'
    and (pg_temp.tx('x3c')::jsonb)->>'status' = 'not_found'
    and (select (o->>'refund_covered')::boolean from jsonb_array_elements(public.event_vip_orders_list(pg_temp.fx('ev'))->'orders') o
          where o->>'order_id' = pg_temp.bid('VIP', 'v1')),
  'X3 HitPay''s refund is noted (a smaller total later changes nothing); Website orders shows it covered once an invoice of that much is cancelled');

-- ═════ G Gifts at the door ═════
select pg_temp.putx('g_cara', (pg_temp.pp(pg_temp.fx('cara'))).vip_guest_id);
select pg_temp.put('g_req', gen_random_uuid()::text);
select pg_temp.as_user('staff');
select pg_temp.put('g1', public.event_vip_gift_give(pg_temp.fx('g_cara'), pg_temp.fx('socks'), pg_temp.d(8), pg_temp.tx('g_req')::uuid)::text);
select pg_temp.check((pg_temp.tx('g1')::jsonb) @> '{"product_name": "HT436 Socks Black", "remaining": 2, "replayed": false}'::jsonb
    and (select current_qty from store_inventory where store_id = pg_temp.fx('van') and product_id = pg_temp.fx('socks')) = 2
    and exists (select 1 from stock_uses u where u.use_no = (pg_temp.tx('g1')::jsonb)->>'use_no' and u.store_id = pg_temp.fx('van')
                  and u.reason = 'Event gift' and u.note = 'HT436 Health Seminar ' || pg_temp.tx('sfx') || ' · VIP gift · Cara Vipguest'
                  and u.used_by = pg_temp.fx('staff'))
    and exists (select 1 from stock_movements m where m.notes like 'Stock use ' || ((pg_temp.tx('g1')::jsonb)->>'use_no') || ' — Event gift%'
                  and m.from_store_id = pg_temp.fx('van') and m.quantity = 1)
    and exists (select 1 from audit_logs a where a.record_id = pg_temp.fx('g_cara') and a.action = 'event_vip_gift_given'),
  'G1 a VIP''s socks at the door: one less at the van, a USE number, a movement, audited: ' || pg_temp.tx('g1'));
select pg_temp.put('g3', public.event_vip_gift_give(pg_temp.fx('g_cara'), pg_temp.fx('socks'), pg_temp.d(8), pg_temp.tx('g_req')::uuid)::text);
select pg_temp.check((pg_temp.tx('g3')::jsonb) @> '{"replayed": true}'::jsonb
    and (select current_qty from store_inventory where store_id = pg_temp.fx('van') and product_id = pg_temp.fx('socks')) = 2,
  'G3 the same request again: the same gift, no second one');
select pg_temp.put('g2_twice', pg_temp.err(format('select public.event_vip_gift_give(%L, %L, null, null)', pg_temp.fx('g_cara'), pg_temp.fx('gloves'))));
select pg_temp.put('g2_free', pg_temp.err(format('select public.event_vip_gift_give(%L, %L, null, null)', (pg_temp.pp(pg_temp.fx('p_r1'))).free_guest_id, pg_temp.fx('gloves'))));
select pg_temp.put('g2_other', pg_temp.err(format('select public.event_vip_gift_give(%L, %L, %L, null)', (pg_temp.pp(pg_temp.fx('bob'))).vip_guest_id, pg_temp.fx('aff'), pg_temp.d(7))));
select pg_temp.put('g2_white', pg_temp.err(format('select public.event_vip_gift_give(%L, %L, %L, null)', (pg_temp.pp(pg_temp.fx('bob'))).vip_guest_id, pg_temp.fx('white'), pg_temp.d(7))));
select pg_temp.as_user('staff2');
select pg_temp.put('g2_store', pg_temp.errcode(format('select public.event_vip_gift_give(%L, %L, %L, null)', (pg_temp.pp(pg_temp.fx('bob'))).vip_guest_id, pg_temp.fx('gloves'), pg_temp.d(7))));
select pg_temp.check(pg_temp.tx('g2_twice') like 'Cara Vipguest already has their gift (HT436 Socks Black, USE-%'
    and pg_temp.tx('g2_free') = 'Nadia Freshperson is not a VIP guest'
    and pg_temp.tx('g2_other') = 'Choose one of the event''s VIP gifts'
    and pg_temp.tx('g2_white') = 'Only 0 of "HT436 Socks White" in stock at this store'
    and pg_temp.tx('g2_store') = '42501',
  'G2 refused: a second gift, a guest who is not VIP, a product that is not a gift, out of stock, staff of another store: '
    || concat_ws(' | ', pg_temp.tx('g2_twice'), pg_temp.tx('g2_free'), pg_temp.tx('g2_other'), pg_temp.tx('g2_white'), pg_temp.tx('g2_store')));
select pg_temp.as_user('staff');
select pg_temp.put('g4_staff', pg_temp.errcode(format('select public.event_vip_gift_undo(%L, %L)', (pg_temp.tx('g1')::jsonb)->>'gift_id', 'Wrong size')));
select pg_temp.as_user('manager');
select pg_temp.put('g4', public.event_vip_gift_undo(((pg_temp.tx('g1')::jsonb)->>'gift_id')::uuid, 'Wrong size, swapped')::text);
select pg_temp.as_user('staff');
select pg_temp.put('g4b', pg_temp.err(format('select public.event_vip_gift_give(%L, %L, null, null)', pg_temp.fx('g_cara'), pg_temp.fx('gloves'))));
select pg_temp.check(pg_temp.tx('g4_staff') = '42501'
    and (pg_temp.tx('g4')::jsonb)->>'message' = format('Put the item back with Stock, Adjust (an adjustment request), quoting %s.', (pg_temp.tx('g1')::jsonb)->>'use_no')
    and pg_temp.tx('g4b') = 'ok'
    and (select current_qty from store_inventory where store_id = pg_temp.fx('van') and product_id = pg_temp.fx('gloves')) = 0,
  'G4 a Manager (not staff) marks a gift undone and is told to put it back by adjustment; another can then be given: ' || pg_temp.tx('g4b'));

-- ═════ Y Sync ═════
select pg_temp.as_user('staff');
select public.event_save_guest(jsonb_build_object('event_id', pg_temp.fx('ev'), 'name', 'Walk In Guest', 'phone', pg_temp.ph(70),
  'days', jsonb_build_array(pg_temp.d(7))));
select pg_temp.as_user('owner');
select pg_temp.putx('counter_inv', public.create_invoice_with_details(pg_temp.fx('van'), pg_temp.fx('c_ken'),
  jsonb_build_array(jsonb_build_object('kind', 'event_ticket', 'event_ticket_option_id', pg_temp.fx('vip'), 'quantity', 1,
    'attendees', jsonb_build_array(jsonb_build_object('name', 'Kenneth Counter')))), jsonb_build_object('business_date', public.sg_today())));
select pg_temp.put('y1', pg_temp.call('live', 'sync', '{}')::text);
select pg_temp.put('y1b', pg_temp.call('live', 'sync', '{}')::text);
create function pg_temp.yrow(match text) returns jsonb language sql as
$$ select x from jsonb_array_elements(pg_temp.tx('y1')::jsonb->'people') x where x->>'name' = match limit 1 $$;
select pg_temp.check((pg_temp.tx('y1')::jsonb) @> jsonb_build_object('ok', true, 'test', false, 'status', 'ok', 'event',
      jsonb_build_object('code', pg_temp.tx('code'), 'venue', 'Hall 2, Example Centre', 'days', jsonb_build_array(pg_temp.d(7), pg_temp.d(8))))
    and pg_temp.yrow('Bob Vipguest') @> jsonb_build_object('key', pg_temp.fx('bob'), 'source', 'website', 'registration_id', pg_temp.bid('REG', 'v1b'),
          'position', 1, 'group_size', 2, 'status', 'registered', 'vip', 'paid', 'vip_method', 'HitPay', 'vip_order_id', pg_temp.bid('VIP', 'v1'),
          'days', jsonb_build_array(pg_temp.d(7), pg_temp.d(8)))
    and pg_temp.yrow('Vera Viplink') @> jsonb_build_object('vip', 'refunded', 'status', 'registered', 'referral_code', pg_temp.tx('code_ok'),
          'days', jsonb_build_array(pg_temp.d(7)))
    and pg_temp.yrow('Jo Paynow') @> '{"vip": "paid", "vip_method": "PayNow"}'::jsonb
    and pg_temp.yrow('Walk In Guest') @> jsonb_build_object('source', 'staff', 'vip', 'none', 'registered_by', 'HT436 Staff ' || pg_temp.tx('sfx'))
    and pg_temp.yrow('Walk In Guest')->>'key' ~ '^GUEST-[0-9A-F]{8}$'
    and pg_temp.yrow('Kenneth Counter') @> '{"source": "counter", "vip": "pending"}'::jsonb
    and pg_temp.yrow('Kenneth Counter')->>'key' ~ '^TICKET-[0-9A-F]{8}$'
    and (select count(*) from jsonb_array_elements(pg_temp.tx('y1')::jsonb->'people') x where x->>'name' = 'Bob Vipguest') = 1
    and not exists (select 1 from jsonb_array_elements(pg_temp.tx('y1')::jsonb->'people') x where x->>'name' like 'Tess%')
    and exists (select 1 from jsonb_array_elements(pg_temp.tx('y1')::jsonb->'vip_orders') o
                 where o @> jsonb_build_object('order_id', pg_temp.bid('VIP', 'v1'), 'provider', 'hitpay', 'status', 'invoiced',
                         'amount_cents', 21600, 'refunded_cents_total', 7200)
                   and jsonb_array_length(o->'invoice_nos') = 3)
    and pg_temp.tx('y1b')::jsonb = '{"ok": true, "test": false, "status": "too_soon"}'::jsonb,
  'Y1 sync: each website person once (VIP state, method, order), staff guests (GUEST-) and counter tickets (TICKET-), the orders; again within a minute: too_soon');
select pg_temp.put('y2', pg_temp.call('test', 'sync', '{}')::text);
select pg_temp.check((pg_temp.tx('y2')::jsonb)->>'status' = 'ok' and (pg_temp.tx('y2')::jsonb)->>'test' = 'true'
    and not exists (select 1 from jsonb_array_elements(pg_temp.tx('y2')::jsonb->'people') x where x->>'source' <> 'website' or x->>'name' not in ('Tess Testing', 'Mei Ling Tan'))
    and jsonb_array_length(pg_temp.tx('y2')::jsonb->'people') = 2,
  'Y2 the test key''s sync lists its test rows only');
select pg_temp.check(public.event_web_sync_ping() = 1, 'Y3 the nudge goes to the website''s sync URL while it is not off');
update event_web_settings set mode = 'off' where event_id = pg_temp.fx('ev');
select pg_temp.check(public.event_web_sync_ping() = 0, 'Y3 and not once it is off');
update event_web_settings set mode = 'live' where event_id = pg_temp.fx('ev');

-- ═════ H To match on the Event page ═════
select pg_temp.as_user('staff');
select pg_temp.put('h1', public.event_web_guest_extras(pg_temp.fx('ev'))::text);
create function pg_temp.hold_of(pid uuid) returns jsonb language sql as
$$ select h from jsonb_array_elements(pg_temp.tx('h1')::jsonb->'holds') h where (h->>'person_id')::uuid = pid $$;
create function pg_temp.extra_of(gid uuid) returns jsonb language sql as
$$ select g from jsonb_array_elements(pg_temp.tx('h1')::jsonb->'guests') g where (g->>'guest_id')::uuid = gid $$;
select pg_temp.check(pg_temp.hold_of((pg_temp.r2(5)).id) @> jsonb_build_object('reason', 'several_name_matches', 'full_name', 'Sam Twin',
        'phone', pg_temp.ph(5), 'vip_waiting', true)
    and (select count(*) from jsonb_array_elements(pg_temp.hold_of((pg_temp.r2(5)).id)->'candidates') c
          where c @> '{"phone_matches": true, "name_matches": true}'::jsonb) = 2
    and pg_temp.hold_of((pg_temp.r2(4)).id) is null
    and pg_temp.extra_of((pg_temp.pp(pg_temp.fx('cara'))).vip_guest_id) @> '{"vip": "paid", "vip_guest": true, "website": true, "upgrade_token": null}'::jsonb
    and pg_temp.extra_of((pg_temp.pp(pg_temp.fx('cara'))).vip_guest_id)->'gift'->>'product_name' = 'HT436 Gloves'
    and pg_temp.extra_of((pg_temp.pp(pg_temp.fx('cara'))).free_guest_id) @> '{"parked": true}'::jsonb
    and pg_temp.extra_of((pg_temp.pp(pg_temp.fx('p_r1'))).free_guest_id)->>'upgrade_token' = (pg_temp.pp(pg_temp.fx('p_r1'))).upgrade_token
    and pg_temp.extra_of((pg_temp.f1(1)).free_guest_id)->'referral' @> jsonb_build_object('code', pg_temp.tx('code_ok'), 'outcome', 'created')
    and pg_temp.extra_of((select id from event_guests where invoice_id = pg_temp.fx('counter_inv'))) @> '{"vip_guest": true, "website": false}'::jsonb
    and (pg_temp.tx('h1')::jsonb)->'gift_choices' = jsonb_build_array(
          jsonb_build_object('product_id', pg_temp.fx('socks'), 'name', 'HT436 Socks Black', 'stock', 2),
          jsonb_build_object('product_id', pg_temp.fx('gloves'), 'name', 'HT436 Gloves', 'stock', 0),
          jsonb_build_object('product_id', pg_temp.fx('white'), 'name', 'HT436 Socks White', 'stock', 0)),
  'H1 staff see who waits to be matched (with whoever has the phone or email), each guest''s VIP, gift, referral and VIP link, and the gifts in stock');
select pg_temp.put('h2_staff', pg_temp.errcode(format('select public.event_registration_close(%L, %L)', (pg_temp.r2(6)).id, 'A test form')));
select pg_temp.as_user('manager');
select pg_temp.put('h2_wait', pg_temp.err(format('select public.event_registration_close(%L, %L)', (pg_temp.r2(5)).id, 'Duplicate')));
select pg_temp.put('h2', pg_temp.err(format('select public.event_registration_close(%L, %L)', (pg_temp.r2(6)).id, 'A test form')));
select pg_temp.put('h2_person', pg_temp.call('live', 'person', jsonb_build_object('upgrade_token', (pg_temp.r2(6)).upgrade_token))::text);
select pg_temp.check(pg_temp.tx('h2_staff') = '42501' and pg_temp.tx('h2_wait') = 'A VIP payment for Sam Twin is waiting: deal with it on Website orders first.'
    and pg_temp.tx('h2') = 'ok' and (pg_temp.r2(6)).match = 'closed'
    and ((pg_temp.guest((pg_temp.r2(6)).free_guest_id)).status, (pg_temp.guest((pg_temp.r2(6)).free_guest_id)).cancelled_reason) = ('cancelled'::text, 'Closed: A test form'::text)
    and (pg_temp.tx('h2_person')::jsonb)->'person'->>'reason' = 'cancelled',
  'H2 an Owner or Manager (not staff) closes a registration that is not real: off the list; not while a VIP payment waits');
-- H3 production-sized: 12,950 customers (three in four with an email) and 50 people waiting to be matched; the Guests
-- and Check-in tabs read them well inside the 8 seconds a signed-in call has (it was a scan of every customer per person).
do $$ begin
  insert into public.customers (full_name, phone, email)
  select 'HT436 Bulk ' || n,
         case when n < 10000 then '+6175550' || lpad(n::text, 4, '0') else '+6185550' || lpad((n - 10000)::text, 4, '0') end,
         case when n % 4 <> 0 then 'ht436-bulk-' || n || '-' || lower(pg_temp.tx('sfx')) || '@example.com' end
    from generate_series(0, 12949) n;
end $$;
analyze public.customers;
do $$ declare r uuid; k int; begin
  for k in 0 .. 4 loop
    insert into public.event_registrations (event_id, registration_id, is_test, submitted_at, people_count, people_md5, referral_state)
    values (pg_temp.fx('ev'), pg_temp.bid('REG', 'h3-' || k), false, now(), 10, md5('h3' || k), 'none') returning id into r;
    insert into public.event_registration_people (registration_ref, event_id, position, first_name, last_name, full_name, phone,
        phone_norm, email, days, match, hold_reason, candidate_customer_ids, upgrade_token)
    select r, pg_temp.fx('ev'), j, 'Held', 'Bulk' || (k * 10 + j), 'Held Bulk' || (k * 10 + j), '+6175550' || lpad((k * 10 + j)::text, 4, '0'),
           '+6175550' || lpad((k * 10 + j)::text, 4, '0'),
           'ht436-bulk-' || (3001 + 2 * (k * 10 + j)) || '-' || lower(pg_temp.tx('sfx')) || '@example.com',
           array[pg_temp.d(7)], 'held', 'phone_and_email_in_use',
           array(select c.id from public.customers c where c.phone = '+6175550' || lpad((k * 10 + j)::text, 4, '0')),
           public.event_web_new_token()
      from generate_series(1, 10) j;
  end loop;
end $$;
select pg_temp.as_user('staff');
do $$ declare t0 timestamptz := clock_timestamp(); v jsonb; begin
  v := public.event_web_guest_extras(pg_temp.fx('ev'));
  perform pg_temp.put('h3_ms', round(extract(epoch from clock_timestamp() - t0) * 1000)::text);
  perform pg_temp.put('h3', v::text);
end $$;
select pg_temp.check(pg_temp.tx('h3_ms')::int < 2000
    and (select count(*) from jsonb_array_elements(pg_temp.tx('h3')::jsonb->'holds') h
          where h->>'full_name' like 'Held Bulk%' and jsonb_array_length(h->'candidates') = 2
            and exists (select 1 from jsonb_array_elements(h->'candidates') c
                         where (c->>'phone_matches')::boolean and not (c->>'email_matches')::boolean and c->>'phone' = h->>'phone')
            and exists (select 1 from jsonb_array_elements(h->'candidates') c
                         where (c->>'email_matches')::boolean and not (c->>'phone_matches')::boolean and c->>'email' = h->>'email')) = 50,
  'H3 50 people to match among 12,950 customers: read in ' || pg_temp.tx('h3_ms') || ' ms (under 2 s), each with the customer on their phone and the one with their email');
-- X5 VIP bought again after a refund: the old VIP invoice is not reopened while the new one stands (two VIP records, two sets of vouchers);
-- once the new one is cancelled, the old one reopens and is their VIP record again.
select pg_temp.checkout('live', 'x5', array[pg_temp.tx('tok:vera')]);
select pg_temp.put('x5p', pg_temp.paid('live', 'x5', array[pg_temp.tx('tok:vera')], 7200)::text);
select pg_temp.putx('inv_vera2', (select i.id from pg_temp.vinvoices('x5') i));
select pg_temp.as_user('owner');
select pg_temp.put('x5_reopen', pg_temp.err(format('select public.reopen_invoice(%L, %L, %L)', pg_temp.fx('inv_vera'), 'Reopened by mistake', gen_random_uuid())));
select pg_temp.check((pg_temp.tx('x5p')::jsonb)->>'status' = 'invoiced'
    and pg_temp.tx('x5_reopen') = format('Vera Viplink already has a newer VIP record (%s). Cancel or refund it before reopening this invoice.',
                                         (select invoice_no from invoices where id = pg_temp.fx('inv_vera2')))
    and (select status::text from invoices where id = pg_temp.fx('inv_vera')) = 'cancelled'
    and (select count(*) from customer_reward_vouchers v where v.customer_id = (pg_temp.pp(pg_temp.fx('vera'))).customer_id and v.status = 'held') = 2
    and (select count(*) from event_guests where event_id = pg_temp.fx('ev') and status = 'registered' and phone = pg_temp.ph(30)) = 1,
  'X5 VIP bought again after a refund; reopening the old VIP invoice is refused, naming the new one: ' || pg_temp.tx('x5_reopen'));
select public.cancel_invoice_recorded(pg_temp.fx('inv_vera2'), 'Paid twice by mistake', gen_random_uuid());
select pg_temp.put('x5_reopen2', pg_temp.err(format('select public.reopen_invoice(%L, %L, %L)', pg_temp.fx('inv_vera'), 'The first one stands', gen_random_uuid())));
select pg_temp.check(pg_temp.tx('x5_reopen2') = 'ok'
    and (pg_temp.pp(pg_temp.fx('vera'))).vip_guest_id = (select g.id from event_guests g where g.invoice_id = pg_temp.fx('inv_vera'))
    and (pg_temp.guest((pg_temp.pp(pg_temp.fx('vera'))).vip_guest_id)).status = 'registered'
    and (pg_temp.guest((pg_temp.pp(pg_temp.fx('vera'))).free_guest_id)).cancelled_reason
        = 'Upgraded to VIP · ' || (select invoice_no from invoices where id = pg_temp.fx('inv_vera'))
    and (select count(*) from event_guests where event_id = pg_temp.fx('ev') and status = 'registered' and phone = pg_temp.ph(30)) = 1
    and (select count(*) from customer_reward_vouchers v where v.customer_id = (pg_temp.pp(pg_temp.fx('vera'))).customer_id and v.status = 'held') = 2
    and public.event_web_person_vip_state(pg_temp.fx('vera')) = 'paid',
  'X5 once the new VIP invoice is cancelled, the old one reopens: its record is their VIP record again, the free one parked, one set of vouchers');


-- ═════ XF Refunded in full (the owner, 20 Oct 2026) ═════
-- Five VIPs on one HitPay payment: Rita (refunded in full, nothing used), Uma (refunded in full, her 3-in-1 used),
-- Pia (part refunds), Cleo (cancelled, its refund recorded first), Dora (refunded straight from the Finance panel).
select pg_temp.put('xf_r', pg_temp.register('live', 'xf', jsonb_build_array(
  pg_temp.person(1, 'Rita', 'Refundfull', pg_temp.ph(120), pg_temp.mail('xf-rita'), array[pg_temp.d(7)], true),
  pg_temp.person(2, 'Uma', 'Usedone', pg_temp.ph(121), pg_temp.mail('xf-uma'), array[pg_temp.d(7)], true),
  pg_temp.person(3, 'Pia', 'Partial', pg_temp.ph(122), pg_temp.mail('xf-pia'), array[pg_temp.d(8)], true),
  pg_temp.person(4, 'Cleo', 'Cancelrec', pg_temp.ph(123), pg_temp.mail('xf-cleo'), array[pg_temp.d(8)], true),
  pg_temp.person(5, 'Dora', 'Direct', pg_temp.ph(124), pg_temp.mail('xf-dora'), array[pg_temp.d(7)], true)))::text);
select pg_temp.putx(k, pg_temp.pid(pg_temp.tx('xf_r')::jsonb, n)) from (values ('rita', 1), ('uma', 2), ('pia', 3), ('cleo', 4), ('dora', 5)) x(k, n);
select pg_temp.put('tok:' || k, pg_temp.tok(pg_temp.tx('xf_r')::jsonb, n)) from (values ('rita', 1), ('uma', 2), ('pia', 3), ('cleo', 4), ('dora', 5)) x(k, n);
select pg_temp.checkout('live', 'xf', array[pg_temp.tx('tok:rita'), pg_temp.tx('tok:uma'), pg_temp.tx('tok:pia'), pg_temp.tx('tok:cleo'), pg_temp.tx('tok:dora')]);
select pg_temp.put('xf_p', pg_temp.paid('live', 'xf', array[pg_temp.tx('tok:rita'), pg_temp.tx('tok:uma'), pg_temp.tx('tok:pia'), pg_temp.tx('tok:cleo'), pg_temp.tx('tok:dora')], 36000)::text);
select pg_temp.putx('inv_' || k, (select i.id from pg_temp.vinvoices('xf') i where i.customer_id = (pg_temp.pp(pg_temp.fx(k))).customer_id))
  from unnest(array['rita', 'uma', 'pia', 'cleo', 'dora']) k;
-- The two VIP vouchers of an invoice, by kind: their status.
create function pg_temp.vstat(inv uuid) returns jsonb language sql as
$$ select coalesce(jsonb_object_agg(case v.voucher_id when pg_temp.fx('save72') then 'save72' when pg_temp.fx('three') then 'three' else v.voucher_id::text end,
                                    v.status), '{}'::jsonb)
     from customer_reward_vouchers v where v.id in (select b.reward_voucher_id from invoice_benefit_values b where b.invoice_id = inv) $$;
create function pg_temp.ticket(inv uuid) returns uuid language sql as
$$ select id from invoice_items where invoice_id = inv and line_kind = 'event_ticket' $$;
create function pg_temp.payment(inv uuid) returns uuid language sql as
$$ select id from invoice_payments where invoice_id = inv order by created_at limit 1 $$;
create function pg_temp.audits(inv uuid, act text) returns bigint language sql as
$$ select count(*) from audit_logs a
    where a.action = act and (a.record_id = inv or a.record_id in (select b.reward_voucher_id from invoice_benefit_values b where b.invoice_id = inv)) $$;
select pg_temp.check((pg_temp.tx('xf_p')::jsonb)->>'status' = 'invoiced'
    and (select count(*) from pg_temp.vinvoices('xf') i where i.status = 'paid') = 5
    and (select bool_and(pg_temp.vstat(i.id) = '{"save72": "held", "three": "held"}'::jsonb) from pg_temp.vinvoices('xf') i),
  'XF0 five VIPs paid at once: five invoices, each VIP holding the S$72 voucher and the 3-in-1: ' || pg_temp.tx('xf_p'));

-- XF1 Rita: Refund in full, nothing used. Staff see first that both vouchers are taken back; a Manager approves.
select pg_temp.as_user('staff');
select pg_temp.put('xf1_plan', public.invoice_action_plan(pg_temp.fx('inv_rita'), 'refund_full', '[]')::text);
select pg_temp.put('xf1_cancel_plan', public.invoice_action_plan(pg_temp.fx('inv_rita'), 'cancel', '[]')::text);
select pg_temp.check((pg_temp.tx('xf1_plan')::jsonb)->'summary' @> jsonb_build_array(
        'Take back the unused HT436 $72 discount Voucher that came with VIP from Rita Refundfull.',
        'Take back the unused HT436 3-in-1 Vouchers that came with VIP from Rita Refundfull.')
    and (pg_temp.tx('xf1_plan')::jsonb)->'effects'->'benefits' @> jsonb_build_array(
        jsonb_build_object('kind', 'voucher', 'holder', 'Rita Refundfull', 'units_revoked', 1, 'line', 'HT436 $72 discount Voucher, included with VIP'),
        jsonb_build_object('kind', 'voucher', 'holder', 'Rita Refundfull', 'units_revoked', 1, 'line', 'HT436 3-in-1 Vouchers, included with VIP'))
    and (pg_temp.tx('xf1_plan')::jsonb)->>'refund_amount' = '72.00'
    and not exists (select 1 from jsonb_array_elements((pg_temp.tx('xf1_plan')::jsonb)->'overrides_required') o where o->>'code' = 'vip_voucher_used')
    and pg_temp.tx('xf1_cancel_plan') !~ 'came with VIP|included with VIP|vip_voucher_used',
  'XF1 the Refund in full plan says first that both unused VIP vouchers are taken back (and lists them under the benefits cancelled); a Cancel plan is as before: ' || pg_temp.tx('xf1_plan'));
-- The same plan read as the database role a signed-in browser has (436's helper is the server's alone, reached through the plan).
select set_config('xf.inv', pg_temp.fx('inv_rita')::text, true);
set role authenticated;
select set_config('xf.plan_auth', public.invoice_action_plan(current_setting('xf.inv')::uuid, 'refund_full', '[]')::text, true);
reset role;
select pg_temp.check((current_setting('xf.plan_auth')::jsonb) - 'window' = (pg_temp.tx('xf1_plan')::jsonb) - 'window'
    and not has_function_privilege('authenticated', 'public.event_vip_refund_plan(uuid,text,jsonb)', 'execute'),
  'XF1 a signed-in member of staff (role authenticated) gets the same plan, though the VIP helper is not theirs to call');
select pg_temp.put('xf1_req', public.request_invoice_action_v2(pg_temp.fx('inv_rita'), 'refund_full', '[]', 'Cannot come after all', null, gen_random_uuid())::text);
select pg_temp.as_user('manager');
select pg_temp.put('xf1_res', public.resolve_invoice_action_v2((pg_temp.tx('xf1_req')::jsonb->>'request_id')::uuid, true, 'Refunded by PayNow',
  pg_temp.tx('xf1_req')::jsonb->'plan'->>'plan_hash', '[]', null, false)::text);
select pg_temp.put('xf1_person', pg_temp.call('live', 'person', jsonb_build_object('upgrade_token', pg_temp.tx('tok:rita')))::text);
select pg_temp.check((pg_temp.tx('xf1_res')::jsonb)->>'status' = 'approved'
    and (select status::text from invoices where id = pg_temp.fx('inv_rita')) = 'refunded'
    and pg_temp.vstat(pg_temp.fx('inv_rita')) = '{"save72": "revoked", "three": "revoked"}'::jsonb
    and (select bool_and(v.notes like '%VIP refunded in full · ' || i.invoice_no || ': taken back unused')
           from customer_reward_vouchers v join invoice_benefit_values b on b.reward_voucher_id = v.id join invoices i on i.id = b.invoice_id
          where b.invoice_id = pg_temp.fx('inv_rita'))
    and (select bool_and(b.cancelled_unused_value = 1) from invoice_benefit_values b where b.invoice_id = pg_temp.fx('inv_rita') and b.reward_voucher_id is not null)
    and pg_temp.audits(pg_temp.fx('inv_rita'), 'vip_voucher_taken_back') = 2
    and (select a.new_data from audit_logs a where a.record_id = pg_temp.fx('inv_rita') and a.action = 'vip_refund_vouchers')->'used_kept' = '[]'::jsonb,
  'XF1 approved: S$72 back, both vouchers taken back as a cancellation records them, each audited: ' || pg_temp.tx('xf1_res'));
select pg_temp.check((pg_temp.guest((pg_temp.pp(pg_temp.fx('rita'))).vip_guest_id)).status = 'cancelled'
    and (pg_temp.guest((pg_temp.pp(pg_temp.fx('rita'))).free_guest_id)).status = 'registered'
    and public.event_web_person_vip_state(pg_temp.fx('rita')) = 'refunded'
    and (pg_temp.tx('xf1_person')::jsonb)->'person' @> '{"vip": "refunded", "can_upgrade": true, "reason": null}'::jsonb
    and (select count(*) from event_guests where event_id = pg_temp.fx('ev') and status = 'registered' and phone = pg_temp.ph(120)) = 1,
  'XF1 Rita is not VIP any more: the VIP record cancelled, her free record back, her VIP link says refunded: ' || pg_temp.tx('xf1_person'));

-- XF2 Uma used her 3-in-1: the plan names it first and the refund needs a reason; it stays recorded as used.
update customer_reward_vouchers set status = 'redeemed', redeemed_at = now()
 where id in (select b.reward_voucher_id from invoice_benefit_values b where b.invoice_id = pg_temp.fx('inv_uma')) and voucher_id = pg_temp.fx('three');
select pg_temp.as_user('staff');
select pg_temp.put('xf2_plan', public.invoice_action_plan(pg_temp.fx('inv_uma'), 'refund_full', '[]')::text);
select pg_temp.check(exists (select 1 from jsonb_array_elements((pg_temp.tx('xf2_plan')::jsonb)->'overrides_required') o
                      where o = jsonb_build_object('code', 'vip_voucher_used', 'message',
                        'Uma Usedone has already used the HT436 3-in-1 Vouchers that came with VIP (' || (select invoice_no from invoices where id = pg_temp.fx('inv_uma'))
                        || '). It stays recorded as used and cannot be taken back; only the unused HT436 $72 discount Voucher is taken back with this refund. '
                        || 'Give a reason to go ahead with this refund, or refund less.'))
    and (pg_temp.tx('xf2_plan')::jsonb)->'summary' @> jsonb_build_array('Take back the unused HT436 $72 discount Voucher that came with VIP from Uma Usedone.')
    and (pg_temp.tx('xf2_plan')::jsonb)->>'requires_override' = 'true'
    and jsonb_array_length((pg_temp.tx('xf2_plan')::jsonb)->'effects'->'benefits') = 1,
  'XF2 the plan says plainly that Uma used the 3-in-1 (it stays recorded), only the S$72 voucher comes back, and asks for a reason: ' || pg_temp.tx('xf2_plan'));
select pg_temp.put('xf2_req', public.request_invoice_action_v2(pg_temp.fx('inv_uma'), 'refund_full', '[]', 'Unhappy with the seminar', null, gen_random_uuid())::text);
select pg_temp.as_user('manager');
select pg_temp.put('xf2_noreason', pg_temp.err(format('select public.resolve_invoice_action_v2(%L, true, %L, %L, %L, null, false)',
  (pg_temp.tx('xf2_req')::jsonb->>'request_id'), 'Refunded', pg_temp.tx('xf2_req')::jsonb->'plan'->>'plan_hash', '[]')));
select pg_temp.check(pg_temp.tx('xf2_noreason') = 'An Owner/Manager override reason is required for: vip_voucher_used'
    and (select status::text from invoices where id = pg_temp.fx('inv_uma')) = 'paid'
    and pg_temp.vstat(pg_temp.fx('inv_uma')) = '{"save72": "held", "three": "redeemed"}'::jsonb,
  'XF2 without a reason the refund is refused, and nothing changes: ' || pg_temp.tx('xf2_noreason'));
select pg_temp.put('xf2_res', public.resolve_invoice_action_v2((pg_temp.tx('xf2_req')::jsonb->>'request_id')::uuid, true, 'Refunded',
  pg_temp.tx('xf2_req')::jsonb->'plan'->>'plan_hash', '[{"code": "vip_voucher_used", "reason": "The Owner agreed a full refund"}]', null, false)::text);
select pg_temp.check((pg_temp.tx('xf2_res')::jsonb)->>'status' = 'approved'
    and (select status::text from invoices where id = pg_temp.fx('inv_uma')) = 'refunded'
    and pg_temp.vstat(pg_temp.fx('inv_uma')) = '{"save72": "revoked", "three": "redeemed"}'::jsonb
    and (select a.new_data->'used_kept' from audit_logs a where a.record_id = pg_temp.fx('inv_uma') and a.action = 'vip_refund_vouchers')
        = (select jsonb_agg(b.reward_voucher_id) from invoice_benefit_values b join customer_reward_vouchers v on v.id = b.reward_voucher_id
            where b.invoice_id = pg_temp.fx('inv_uma') and v.voucher_id = pg_temp.fx('three'))
    and (pg_temp.guest((pg_temp.pp(pg_temp.fx('uma'))).free_guest_id)).status = 'registered'
    and public.event_web_person_vip_state(pg_temp.fx('uma')) = 'refunded',
  'XF2 with the reason: refunded, the unused S$72 voucher taken back, the used 3-in-1 stays recorded (named on the invoice''s audit row), Uma not VIP any more');

-- XF3 Pia: a part refund (S$20, from the Finance panel) leaves her VIP with both vouchers; refunding the rest takes them back.
select pg_temp.as_user('owner');
select pg_temp.put('xf3_part', public.refund_invoice_recorded(pg_temp.fx('inv_pia'),
  jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.ticket(pg_temp.fx('inv_pia')), 'amount', 20)),
  jsonb_build_array(jsonb_build_object('payment_id', pg_temp.payment(pg_temp.fx('inv_pia')), 'amount', 20)), '[]', 'Goodwill', gen_random_uuid())::text);
select pg_temp.put('xf3_plan', public.invoice_action_plan(pg_temp.fx('inv_pia'), 'refund_full', '[]')::text);
select pg_temp.check((select status::text from invoices where id = pg_temp.fx('inv_pia')) = 'paid'
    and pg_temp.vstat(pg_temp.fx('inv_pia')) = '{"save72": "held", "three": "held"}'::jsonb
    and (pg_temp.guest((pg_temp.pp(pg_temp.fx('pia'))).vip_guest_id)).status = 'registered'
    and public.event_web_person_vip_state(pg_temp.fx('pia')) = 'paid'
    and pg_temp.audits(pg_temp.fx('inv_pia'), 'vip_voucher_taken_back') = 0
    and (pg_temp.tx('xf3_plan')::jsonb)->>'refund_amount' = '52.00'
    and jsonb_array_length((pg_temp.tx('xf3_plan')::jsonb)->'effects'->'benefits') = 2,
  'XF3 a part refund (S$20 of S$72): still VIP with both vouchers; Refund in full of the rest (S$52) says it takes them back: ' || pg_temp.tx('xf3_part'));
select public.refund_invoice_recorded(pg_temp.fx('inv_pia'),
  jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.ticket(pg_temp.fx('inv_pia')), 'amount', 52)),
  jsonb_build_array(jsonb_build_object('payment_id', pg_temp.payment(pg_temp.fx('inv_pia')), 'amount', 52)), '[]', 'The rest', gen_random_uuid());
select pg_temp.check((select status::text from invoices where id = pg_temp.fx('inv_pia')) = 'refunded'
    and pg_temp.vstat(pg_temp.fx('inv_pia')) = '{"save72": "revoked", "three": "revoked"}'::jsonb
    and (pg_temp.guest((pg_temp.pp(pg_temp.fx('pia'))).free_guest_id)).status = 'registered'
    and public.event_web_person_vip_state(pg_temp.fx('pia')) = 'refunded',
  'XF3 the rest refunded: both vouchers taken back, Pia not VIP any more');

-- XF4 Cleo: Cancel with its refund recorded (the cancellation takes the vouchers back itself, as before).
select pg_temp.as_user('staff');
select pg_temp.put('xf4_req', public.request_invoice_action_v2(pg_temp.fx('inv_cleo'), 'cancel', '[]', 'Wrong person', null, gen_random_uuid())::text);
select pg_temp.as_user('manager');
select pg_temp.put('xf4_res', public.resolve_invoice_action_v2((pg_temp.tx('xf4_req')::jsonb->>'request_id')::uuid, true, 'Cancelled',
  pg_temp.tx('xf4_req')::jsonb->'plan'->>'plan_hash', '[]', null, true)::text);
select pg_temp.check((pg_temp.tx('xf4_res')::jsonb)->>'refund_recorded' = 'true'
    and (select status::text from invoices where id = pg_temp.fx('inv_cleo')) = 'cancelled'
    and pg_temp.vstat(pg_temp.fx('inv_cleo')) = '{"save72": "revoked", "three": "revoked"}'::jsonb
    and (select bool_and(v.notes like '%Cancelled invoice: Cancelled') from customer_reward_vouchers v
          where v.id in (select b.reward_voucher_id from invoice_benefit_values b where b.invoice_id = pg_temp.fx('inv_cleo')))
    and pg_temp.audits(pg_temp.fx('inv_cleo'), 'vip_voucher_taken_back') = 0
    and pg_temp.audits(pg_temp.fx('inv_cleo'), 'vip_refund_vouchers') = 0
    and (pg_temp.guest((pg_temp.pp(pg_temp.fx('cleo'))).free_guest_id)).status = 'registered'
    and pg_temp.tx('xf4_req') !~ 'came with VIP|vip_voucher_used',
  'XF4 Cancel (its S$72 recorded as returned) is as before: the cancellation takes both vouchers back, the free record comes back: ' || pg_temp.tx('xf4_res'));

-- XF5 Dora: refunded in full straight from the Finance panel; then every replay changes nothing.
select pg_temp.as_user('owner');
select pg_temp.put('xf5_req', gen_random_uuid()::text);
select pg_temp.put('xf5_1', public.refund_invoice_recorded(pg_temp.fx('inv_dora'),
  jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.ticket(pg_temp.fx('inv_dora')), 'amount', 72)),
  jsonb_build_array(jsonb_build_object('payment_id', pg_temp.payment(pg_temp.fx('inv_dora')), 'amount', 72)), '[]', 'Refund in full', pg_temp.tx('xf5_req')::uuid)::text);
select pg_temp.put('xf5_2', public.refund_invoice_recorded(pg_temp.fx('inv_dora'),
  jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.ticket(pg_temp.fx('inv_dora')), 'amount', 72)),
  jsonb_build_array(jsonb_build_object('payment_id', pg_temp.payment(pg_temp.fx('inv_dora')), 'amount', 72)), '[]', 'Refund in full', pg_temp.tx('xf5_req')::uuid)::text);
select pg_temp.as_user('manager');
select pg_temp.put('xf5_3', public.resolve_invoice_action_v2((pg_temp.tx('xf1_req')::jsonb->>'request_id')::uuid, true, 'Again',
  pg_temp.tx('xf1_req')::jsonb->'plan'->>'plan_hash', '[]', null, false)::text);
update invoices set paid_amount = paid_amount where id in (pg_temp.fx('inv_rita'), pg_temp.fx('inv_dora'));
select pg_temp.check(pg_temp.vstat(pg_temp.fx('inv_dora')) = '{"save72": "revoked", "three": "revoked"}'::jsonb
    and (pg_temp.tx('xf5_2')::jsonb)->>'replayed' = 'true'
    and (pg_temp.tx('xf5_3')::jsonb)->>'already_resolved' = 'true'
    and pg_temp.audits(pg_temp.fx('inv_dora'), 'vip_voucher_taken_back') = 2 and pg_temp.audits(pg_temp.fx('inv_dora'), 'vip_refund_vouchers') = 1
    and pg_temp.audits(pg_temp.fx('inv_rita'), 'vip_voucher_taken_back') = 2 and pg_temp.audits(pg_temp.fx('inv_rita'), 'vip_refund_vouchers') = 1
    and (select count(*) from invoice_refunds where invoice_id = pg_temp.fx('inv_dora')) = 1
    and (select bool_and(b.cancelled_unused_value = 1) from invoice_benefit_values b where b.invoice_id in (pg_temp.fx('inv_rita'), pg_temp.fx('inv_dora'))
                                                                                and b.reward_voucher_id is not null),
  'XF5 refunded from the Finance panel: both taken back; the same refund again, the approval again and another save of the invoice change nothing');

-- XF6 VIP bought again after the refund: nothing until it is paid, then one new invoice and one new set.
select pg_temp.put('xf6_c', pg_temp.checkout('live', 'xf6', array[pg_temp.tx('tok:rita')])::text);
select pg_temp.put('xf6_held_unpaid', (select count(*) from customer_reward_vouchers v where v.customer_id = (pg_temp.pp(pg_temp.fx('rita'))).customer_id and v.status = 'held')::text);
select pg_temp.put('xf6_p', pg_temp.paid('live', 'xf6', array[pg_temp.tx('tok:rita')], 7200)::text);
select pg_temp.as_user('owner');
select pg_temp.put('xf6_reopen', pg_temp.err(format('select public.reopen_invoice(%L, %L, %L)', pg_temp.fx('inv_rita'), 'Reopened by mistake', gen_random_uuid())));
select pg_temp.check((pg_temp.tx('xf6_c')::jsonb)->>'status' = 'ok' and pg_temp.tx('xf6_held_unpaid') = '0'
    and (pg_temp.tx('xf6_p')::jsonb)->>'status' = 'invoiced'
    and (select count(*) from pg_temp.vinvoices('xf6') i where i.status = 'paid' and i.total_amount = 72) = 1
    and (select count(*) from customer_reward_vouchers v where v.customer_id = (pg_temp.pp(pg_temp.fx('rita'))).customer_id and v.status = 'held') = 2
    and (select count(*) from customer_reward_vouchers v where v.customer_id = (pg_temp.pp(pg_temp.fx('rita'))).customer_id) = 4
    and public.event_web_person_vip_state(pg_temp.fx('rita')) = 'paid'
    and (select count(*) from event_guests where event_id = pg_temp.fx('ev') and status = 'registered' and phone = pg_temp.ph(120)) = 1
    and pg_temp.tx('xf6_reopen') <> 'ok'
    and (select status::text from invoices where id = pg_temp.fx('inv_rita')) = 'refunded',
  'XF6 Rita buys VIP again: no voucher while the payment is only started; paid, one new S$72 invoice and one new set (the old set stays taken back); the refunded invoice is not reopened over it: ' || pg_temp.tx('xf6_reopen'));

-- XF7 limited voucher stock: Refund in full gives each unused VIP voucher back to the van's stock once; a later Cancel gives nothing more.
-- XF8 the guided part refund (by line and units) of the VIP ticket takes them back as Refund in full does (XF12: of another line, nothing).
select pg_temp.as_user('owner');
update vouchers set qty_type = 'limited' where id in (pg_temp.fx('save72'), pg_temp.fx('three'));
insert into voucher_store_stock(voucher_id, store_id, current_qty) values (pg_temp.fx('save72'), pg_temp.fx('van'), 50), (pg_temp.fx('three'), pg_temp.fx('van'), 50)
  on conflict (voucher_id, store_id) do update set current_qty = 50;
create function pg_temp.vstock() returns text language sql as
$$ select string_agg(current_qty::text, '/' order by voucher_id = pg_temp.fx('three')) from voucher_store_stock
    where store_id = pg_temp.fx('van') and voucher_id in (pg_temp.fx('save72'), pg_temp.fx('three')) $$;
select pg_temp.put('xf7_r', pg_temp.register('live', 'xf7', jsonb_build_array(
  pg_temp.person(1, 'Opal', 'Limited', pg_temp.ph(125), pg_temp.mail('xf7-opal'), array[pg_temp.d(7)], true),
  pg_temp.person(2, 'Quin', 'Partplan', pg_temp.ph(126), pg_temp.mail('xf7-quin'), array[pg_temp.d(7)], true)))::text);
select pg_temp.putx(k, pg_temp.pid(pg_temp.tx('xf7_r')::jsonb, n)) from (values ('opal', 1), ('quin', 2)) x(k, n);
select pg_temp.put('tok:' || k, pg_temp.tok(pg_temp.tx('xf7_r')::jsonb, n)) from (values ('opal', 1), ('quin', 2)) x(k, n);
select pg_temp.checkout('live', 'xf7', array[pg_temp.tx('tok:opal'), pg_temp.tx('tok:quin')]);
select pg_temp.paid('live', 'xf7', array[pg_temp.tx('tok:opal'), pg_temp.tx('tok:quin')], 14400);
select pg_temp.putx('inv_' || k, (select i.id from pg_temp.vinvoices('xf7') i where i.customer_id = (pg_temp.pp(pg_temp.fx(k))).customer_id))
  from unnest(array['opal', 'quin']) k;
select pg_temp.put('xf7_s0', pg_temp.vstock());
select pg_temp.as_user('owner');
select public.refund_invoice_recorded(pg_temp.fx('inv_opal'),
  jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.ticket(pg_temp.fx('inv_opal')), 'amount', 72)),
  jsonb_build_array(jsonb_build_object('payment_id', pg_temp.payment(pg_temp.fx('inv_opal')), 'amount', 72)), '[]', 'Refund in full', gen_random_uuid());
select pg_temp.put('xf7_s1', pg_temp.vstock());
select pg_temp.put('xf7_cancel', pg_temp.err(format('select public.cancel_invoice_recorded(%L, %L, %L)', pg_temp.fx('inv_opal'), 'Cancelled after the refund', gen_random_uuid())));
select pg_temp.check(pg_temp.tx('xf7_s0') = '48/48' and pg_temp.tx('xf7_s1') = '49/49' and pg_temp.vstock() = '49/49'
    and pg_temp.tx('xf7_cancel') = 'ok'
    and pg_temp.vstat(pg_temp.fx('inv_opal')) = '{"save72": "revoked", "three": "revoked"}'::jsonb,
  'XF7 limited stock: paid ' || pg_temp.tx('xf7_s0') || ', refunded in full ' || pg_temp.tx('xf7_s1') || ', cancelled after (' || pg_temp.tx('xf7_cancel') || ') ' || pg_temp.vstock());
select pg_temp.as_user('staff');
select pg_temp.put('xf8_plan', public.invoice_action_plan(pg_temp.fx('inv_quin'), 'refund_partial',
  jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.ticket(pg_temp.fx('inv_quin')), 'quantity', 1)))::text);
select pg_temp.check((pg_temp.tx('xf8_plan')::jsonb)->'summary' @> jsonb_build_array(
          'Take back the unused HT436 $72 discount Voucher that came with VIP from Quin Partplan.',
          'Take back the unused HT436 3-in-1 Vouchers that came with VIP from Quin Partplan.')
    and (pg_temp.tx('xf8_plan')::jsonb)->>'refund_amount' = '72.00'
    and jsonb_array_length((pg_temp.tx('xf8_plan')::jsonb)->'effects'->'benefits') = 2,
  'XF8 the guided part refund of the VIP ticket line says first that both VIP vouchers are taken back: ' || left(pg_temp.tx('xf8_plan'), 600));
select pg_temp.as_user('owner');
update vouchers set qty_type = 'unlimited' where id in (pg_temp.fx('save72'), pg_temp.fx('three'));

-- XF9 a VIP voucher moved to another customer (the Finance panel's Move) is not "used": its replacement is taken back.
-- Gil: his S$72 voucher moved to Hal; the guided Refund in full takes back Hal's and Gil's 3-in-1, no reason needed;
-- once Hal has used it, the plan names Hal (only the 3-in-1 "is" taken back) and the audit keeps Hal's voucher alone.
-- Ike: his S$72 voucher moved to Max, then refunded straight from the Finance panel: both taken back, nothing named used.
select pg_temp.put('xf9_r', pg_temp.register('live', 'xf9', jsonb_build_array(
  pg_temp.person(1, 'Gil', 'Movedone', pg_temp.ph(127), pg_temp.mail('xf9-gil'), array[pg_temp.d(7)], true),
  pg_temp.person(2, 'Ike', 'Movedpanel', pg_temp.ph(128), pg_temp.mail('xf9-ike'), array[pg_temp.d(7)], true)))::text);
select pg_temp.putx(k, pg_temp.pid(pg_temp.tx('xf9_r')::jsonb, n)) from (values ('gil', 1), ('ike', 2)) x(k, n);
select pg_temp.put('tok:' || k, pg_temp.tok(pg_temp.tx('xf9_r')::jsonb, n)) from (values ('gil', 1), ('ike', 2)) x(k, n);
select pg_temp.checkout('live', 'xf9', array[pg_temp.tx('tok:gil'), pg_temp.tx('tok:ike')]);
select pg_temp.paid('live', 'xf9', array[pg_temp.tx('tok:gil'), pg_temp.tx('tok:ike')], 14400);
select pg_temp.putx('inv_' || k, (select i.id from pg_temp.vinvoices('xf9') i where i.customer_id = (pg_temp.pp(pg_temp.fx(k))).customer_id))
  from unnest(array['gil', 'ike']) k;
insert into customers(full_name, phone) values ('Hal Receiver', pg_temp.ph(160)), ('Max Receiver', pg_temp.ph(161));
select pg_temp.putx('hal', (select id from customers where phone = pg_temp.ph(160)));
select pg_temp.putx('max', (select id from customers where phone = pg_temp.ph(161)));
create function pg_temp.save72b(inv uuid) returns uuid language sql as
$$ select b.id from invoice_benefit_values b join customer_reward_vouchers v on v.id = b.reward_voucher_id
    where b.invoice_id = inv and v.voucher_id = pg_temp.fx('save72') and v.status = 'held' $$;
select pg_temp.as_user('owner');
select pg_temp.put('xf9_move', public.transfer_invoice_unused_benefit(pg_temp.save72b(pg_temp.fx('inv_gil')), pg_temp.fx('hal'), pg_temp.fx('van'),
  'Given to his brother', gen_random_uuid())::text);
select pg_temp.as_user('staff');
select pg_temp.put('xf9_plan', public.invoice_action_plan(pg_temp.fx('inv_gil'), 'refund_full', '[]')::text);
select pg_temp.check((pg_temp.tx('xf9_plan')::jsonb)->'summary' @> jsonb_build_array(
        'Take back the unused HT436 $72 discount Voucher that came with VIP from Hal Receiver.',
        'Take back the unused HT436 3-in-1 Vouchers that came with VIP from Gil Movedone.')
    and pg_temp.tx('xf9_plan') !~ 'vip_voucher_used|already used'
    and coalesce((pg_temp.tx('xf9_plan')::jsonb)->>'requires_override', 'false') = 'false',
  'XF9 a voucher moved to Hal is not used: the Refund in full plan takes it back from Hal (and the 3-in-1 from Gil), no reason needed: ' || pg_temp.tx('xf9_plan'));
update customer_reward_vouchers set status = 'redeemed', redeemed_at = now() where customer_id = pg_temp.fx('hal') and status = 'held';
select pg_temp.put('xf9_plan2', public.invoice_action_plan(pg_temp.fx('inv_gil'), 'refund_full', '[]')::text);
select pg_temp.check((select jsonb_agg(o) from jsonb_array_elements((pg_temp.tx('xf9_plan2')::jsonb)->'overrides_required') o where o->>'code' = 'vip_voucher_used')
      = jsonb_build_array(jsonb_build_object('code', 'vip_voucher_used', 'message',
        'Hal Receiver has already used the HT436 $72 discount Voucher that came with VIP (' || (select invoice_no from invoices where id = pg_temp.fx('inv_gil'))
        || '). It stays recorded as used and cannot be taken back; only the unused HT436 3-in-1 Vouchers is taken back with this refund. '
        || 'Give a reason to go ahead with this refund, or refund less.')),
  'XF9 once Hal has used it, the plan names Hal (the one who used it), and only the 3-in-1 is taken back: ' || pg_temp.tx('xf9_plan2'));
select pg_temp.put('xf9_req', public.request_invoice_action_v2(pg_temp.fx('inv_gil'), 'refund_full', '[]', 'Cannot come', null, gen_random_uuid())::text);
select pg_temp.as_user('manager');
select pg_temp.put('xf9_res', public.resolve_invoice_action_v2((pg_temp.tx('xf9_req')::jsonb->>'request_id')::uuid, true, 'Refunded',
  pg_temp.tx('xf9_req')::jsonb->'plan'->>'plan_hash', '[{"code": "vip_voucher_used", "reason": "His brother used it; refunded in full all the same"}]', null, false)::text);
select pg_temp.check((pg_temp.tx('xf9_res')::jsonb)->>'status' = 'approved'
    and (select status::text from invoices where id = pg_temp.fx('inv_gil')) = 'refunded'
    and (select a.new_data->'used_kept' from audit_logs a where a.record_id = pg_temp.fx('inv_gil') and a.action = 'vip_refund_vouchers')
        = (select jsonb_agg(v.id) from customer_reward_vouchers v where v.customer_id = pg_temp.fx('hal'))
    and (select count(*) from customer_reward_vouchers v where v.customer_id = (pg_temp.pp(pg_temp.fx('gil'))).customer_id and v.status = 'held') = 0
    and public.event_web_person_vip_state(pg_temp.fx('gil')) = 'refunded',
  'XF9 refunded with the reason: the audit names only Hal''s used voucher (not the moved original), Gil''s 3-in-1 taken back: ' || pg_temp.tx('xf9_res'));
select pg_temp.as_user('owner');
select public.transfer_invoice_unused_benefit(pg_temp.save72b(pg_temp.fx('inv_ike')), pg_temp.fx('max'), pg_temp.fx('van'), 'Given to a friend', gen_random_uuid());
select pg_temp.put('xf9_ike', pg_temp.err(format('select public.refund_invoice_recorded(%L, %L, %L, %L, %L, %L)', pg_temp.fx('inv_ike'),
  jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.ticket(pg_temp.fx('inv_ike')), 'amount', 72)),
  jsonb_build_array(jsonb_build_object('payment_id', pg_temp.payment(pg_temp.fx('inv_ike')), 'amount', 72)), '[]', 'Refund in full', gen_random_uuid())));
select pg_temp.check(pg_temp.tx('xf9_ike') = 'ok'
    and (select status::text from invoices where id = pg_temp.fx('inv_ike')) = 'refunded'
    and (select count(*) from customer_reward_vouchers v where v.customer_id = pg_temp.fx('max') and v.status = 'held') = 0
    and (select count(*) from customer_reward_vouchers v where v.customer_id = (pg_temp.pp(pg_temp.fx('ike'))).customer_id and v.status = 'held') = 0
    and (select a.new_data->'used_kept' from audit_logs a where a.record_id = pg_temp.fx('inv_ike') and a.action = 'vip_refund_vouchers') = '[]'::jsonb
    and jsonb_array_length((select a.new_data->'taken_back' from audit_logs a where a.record_id = pg_temp.fx('inv_ike') and a.action = 'vip_refund_vouchers')) = 2,
  'XF9 Ike''s voucher moved to Max, refunded from the Finance panel: Max''s and Ike''s 3-in-1 taken back, nothing named used: ' || pg_temp.tx('xf9_ike'));

-- XF10 Kim: refunded in full, then her VIP invoice reopened (unpaid). She reads pending, not paid; no second VIP is sold
-- over the open invoice; closing her registration names that invoice; paid again, she is VIP with one set again.
select pg_temp.put('xf10_r', pg_temp.register('live', 'xf10', jsonb_build_array(
  pg_temp.person(1, 'Kim', 'Reopened', pg_temp.ph(129), pg_temp.mail('xf10-kim'), array[pg_temp.d(8)], true)))::text);
select pg_temp.putx('kim', pg_temp.pid(pg_temp.tx('xf10_r')::jsonb, 1));
select pg_temp.put('tok:kim', pg_temp.tok(pg_temp.tx('xf10_r')::jsonb, 1));
select pg_temp.checkout('live', 'xf10', array[pg_temp.tx('tok:kim')]);
select pg_temp.paid('live', 'xf10', array[pg_temp.tx('tok:kim')], 7200);
select pg_temp.putx('inv_kim', (select i.id from pg_temp.vinvoices('xf10') i));
select pg_temp.as_user('owner');
select public.refund_invoice_recorded(pg_temp.fx('inv_kim'),
  jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.ticket(pg_temp.fx('inv_kim')), 'amount', 72)),
  jsonb_build_array(jsonb_build_object('payment_id', pg_temp.payment(pg_temp.fx('inv_kim')), 'amount', 72)), '[]', 'Refund in full', gen_random_uuid());
select pg_temp.put('xf10_s0', public.event_web_person_vip_state(pg_temp.fx('kim')));
select pg_temp.put('xf10_reopen', pg_temp.err(format('select public.reopen_invoice(%L, %L, %L)', pg_temp.fx('inv_kim'), 'Refunded by mistake', gen_random_uuid())));
select pg_temp.put('xf10_person', pg_temp.call('live', 'person', jsonb_build_object('upgrade_token', pg_temp.tx('tok:kim')))::text);
select pg_temp.put('xf10_co', pg_temp.checkout('live', 'xf10b', array[pg_temp.tx('tok:kim')])::text);
select pg_temp.put('xf10_close', pg_temp.err(format('select public.event_registration_close(%L, %L)', pg_temp.fx('kim'), 'Not coming')));
select pg_temp.check(pg_temp.tx('xf10_s0') = 'refunded' and pg_temp.tx('xf10_reopen') = 'ok'
    and (select status::text from invoices where id = pg_temp.fx('inv_kim')) = 'unpaid'
    and public.event_web_person_vip_state(pg_temp.fx('kim')) = 'pending'
    and (pg_temp.tx('xf10_person')::jsonb)->'person' @> '{"vip": "pending", "can_upgrade": false, "reason": "payment_waiting"}'::jsonb
    and (pg_temp.tx('xf10_co')::jsonb) @> '{"status": "refused", "reason": "payment_waiting"}'::jsonb
    and (select count(*) from event_vip_orders where order_id = pg_temp.bid('VIP', 'xf10b') and status = 'pending') = 0
    and pg_temp.tx('xf10_close') = 'Kim Reopened''s VIP invoice ' || (select invoice_no from invoices where id = pg_temp.fx('inv_kim'))
                                   || ' is waiting to be paid: cancel or refund it instead.'
    and (select count(*) from customer_reward_vouchers v where v.customer_id = (pg_temp.pp(pg_temp.fx('kim'))).customer_id and v.status = 'held') = 0,
  'XF10 her refunded VIP invoice reopened (unpaid): she reads pending (payment_waiting), a second VIP checkout is refused, closing names the invoice, no voucher yet: '
  || pg_temp.tx('xf10_co') || ' | ' || pg_temp.tx('xf10_close'));
select public.record_invoice_payment(pg_temp.fx('inv_kim'), jsonb_build_array(jsonb_build_object(
  'payment_method_id', pg_temp.fx('hitpay'), 'amount', 72, 'reference', 'Paid again', 'payment_date', public.sg_today())), gen_random_uuid());
select pg_temp.put('xf10_person2', pg_temp.call('live', 'person', jsonb_build_object('upgrade_token', pg_temp.tx('tok:kim')))::text);
select pg_temp.check((select status::text from invoices where id = pg_temp.fx('inv_kim')) = 'paid'
    and public.event_web_person_vip_state(pg_temp.fx('kim')) = 'paid'
    and (pg_temp.tx('xf10_person2')::jsonb)->'person' @> '{"vip": "paid", "can_upgrade": false, "reason": "already_vip"}'::jsonb
    and (select count(*) from customer_reward_vouchers v where v.customer_id = (pg_temp.pp(pg_temp.fx('kim'))).customer_id and v.status = 'held') = 2,
  'XF10 paid again: VIP (paid) with one set of vouchers again: ' || pg_temp.tx('xf10_person2'));

-- XF11 Ned used his 3-in-1: a refund of his VIP ticket straight from the Finance panel is refused (staff are told first only
-- by Refund in full); a part refund there still goes; the rest through Refund in full, with a reason; a later change to the
-- invoice is not refused for it.
select pg_temp.put('xf11_r', pg_temp.register('live', 'xf11', jsonb_build_array(
  pg_temp.person(1, 'Ned', 'Usedpanel', pg_temp.ph(130), pg_temp.mail('xf11-ned'), array[pg_temp.d(7)], true)))::text);
select pg_temp.putx('ned', pg_temp.pid(pg_temp.tx('xf11_r')::jsonb, 1));
select pg_temp.put('tok:ned', pg_temp.tok(pg_temp.tx('xf11_r')::jsonb, 1));
select pg_temp.checkout('live', 'xf11', array[pg_temp.tx('tok:ned')]);
select pg_temp.paid('live', 'xf11', array[pg_temp.tx('tok:ned')], 7200);
select pg_temp.putx('inv_ned', (select i.id from pg_temp.vinvoices('xf11') i));
update customer_reward_vouchers set status = 'redeemed', redeemed_at = now()
 where id in (select b.reward_voucher_id from invoice_benefit_values b where b.invoice_id = pg_temp.fx('inv_ned')) and voucher_id = pg_temp.fx('three');
select pg_temp.as_user('owner');
select pg_temp.put('xf11_full', pg_temp.err(format('select public.refund_invoice_recorded(%L, %L, %L, %L, %L, %L)', pg_temp.fx('inv_ned'),
  jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.ticket(pg_temp.fx('inv_ned')), 'amount', 72)),
  jsonb_build_array(jsonb_build_object('payment_id', pg_temp.payment(pg_temp.fx('inv_ned')), 'amount', 72)), '[]', 'Refund in full', gen_random_uuid())));
select pg_temp.check(pg_temp.tx('xf11_full') = 'A voucher that came with VIP on ' || (select invoice_no from invoices where id = pg_temp.fx('inv_ned'))
        || ' has already been used, so this refund is not recorded here. Use Refund in full on the invoice: it says which voucher first and asks for a reason.'
    and (select status::text from invoices where id = pg_temp.fx('inv_ned')) = 'paid'
    and (select count(*) from invoice_refunds where invoice_id = pg_temp.fx('inv_ned')) = 0
    and pg_temp.vstat(pg_temp.fx('inv_ned')) = '{"save72": "held", "three": "redeemed"}'::jsonb,
  'XF11 the Finance panel''s refund of the VIP ticket is refused while a VIP voucher is used, and nothing changes: ' || pg_temp.tx('xf11_full'));
select pg_temp.put('xf11_part', pg_temp.err(format('select public.refund_invoice_recorded(%L, %L, %L, %L, %L, %L)', pg_temp.fx('inv_ned'),
  jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.ticket(pg_temp.fx('inv_ned')), 'amount', 20)),
  jsonb_build_array(jsonb_build_object('payment_id', pg_temp.payment(pg_temp.fx('inv_ned')), 'amount', 20)), '[]', 'Goodwill', gen_random_uuid())));
select pg_temp.put('xf11_rest', pg_temp.err(format('select public.refund_invoice_recorded(%L, %L, %L, %L, %L, %L)', pg_temp.fx('inv_ned'),
  jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.ticket(pg_temp.fx('inv_ned')), 'amount', 52)),
  jsonb_build_array(jsonb_build_object('payment_id', pg_temp.payment(pg_temp.fx('inv_ned')), 'amount', 52)), '[]', 'The rest', gen_random_uuid())));
select pg_temp.check(pg_temp.tx('xf11_part') = 'ok' and pg_temp.tx('xf11_rest') like 'A voucher that came with VIP on % has already been used%'
    and (select status::text from invoices where id = pg_temp.fx('inv_ned')) = 'paid'
    and pg_temp.vstat(pg_temp.fx('inv_ned')) = '{"save72": "held", "three": "redeemed"}'::jsonb
    and public.event_web_person_vip_state(pg_temp.fx('ned')) = 'paid',
  'XF11 a part refund there (S$20) still goes, still VIP; the rest (S$52) from the panel is refused: ' || pg_temp.tx('xf11_part') || ' | ' || pg_temp.tx('xf11_rest'));
select pg_temp.as_user('staff');
select pg_temp.put('xf11_req', public.request_invoice_action_v2(pg_temp.fx('inv_ned'), 'refund_full', '[]', 'Cannot come', null, gen_random_uuid())::text);
select pg_temp.as_user('manager');
select pg_temp.put('xf11_res', public.resolve_invoice_action_v2((pg_temp.tx('xf11_req')::jsonb->>'request_id')::uuid, true, 'Refunded',
  pg_temp.tx('xf11_req')::jsonb->'plan'->>'plan_hash', '[{"code": "vip_voucher_used", "reason": "The Owner agreed"}]', null, false)::text);
create function pg_temp.undone_paid_change(inv uuid) returns text language plpgsql as
$$begin
  begin
    update invoices set paid_amount = paid_amount + 1 where id = inv;
    raise exception 'UNDONE %', pg_temp.vstat(inv);
  exception when others then return sqlerrm;
  end;
end$$;
-- A later request is its own transaction: the approval resolved above is no longer named in it.
select pg_temp.as_user('owner'), set_config('invoice.therapy_reviewed', '', true);
select pg_temp.put('xf11_later', pg_temp.undone_paid_change(pg_temp.fx('inv_ned')));
select pg_temp.check((pg_temp.tx('xf11_res')::jsonb)->>'status' = 'approved'
    and (select status::text from invoices where id = pg_temp.fx('inv_ned')) = 'refunded'
    and pg_temp.vstat(pg_temp.fx('inv_ned')) = '{"save72": "revoked", "three": "redeemed"}'::jsonb
    and public.event_web_person_vip_state(pg_temp.fx('ned')) = 'refunded'
    and pg_temp.tx('xf11_later') = 'UNDONE {"three": "redeemed", "save72": "revoked"}',
  'XF11 the rest through Refund in full with a reason: refunded, the S$72 voucher taken back, the 3-in-1 stays used; a later change to the invoice is not refused: '
  || pg_temp.tx('xf11_later'));

-- XF12 Rex: a VIP invoice with a 3-in-1 bought on top (a paid line): his VIP ticket refunded in full takes back only the
-- voucher included with VIP; the paid 3-in-1 is the normal refund flow's (left with him here).
-- Sol: a deleted VIP invoice changes nothing (its vouchers stay as they are).
select pg_temp.put('xf12_r', pg_temp.register('live', 'xf12', jsonb_build_array(
  pg_temp.person(1, 'Rex', 'Extraline', pg_temp.ph(131), pg_temp.mail('xf12-rex'), array[pg_temp.d(7)], false),
  pg_temp.person(2, 'Sol', 'Deleted', pg_temp.ph(132), pg_temp.mail('xf12-sol'), array[pg_temp.d(7)], true)))::text);
select pg_temp.putx(k, pg_temp.pid(pg_temp.tx('xf12_r')::jsonb, n)) from (values ('rex', 1), ('sol', 2)) x(k, n);
select pg_temp.put('tok:sol', pg_temp.tok(pg_temp.tx('xf12_r')::jsonb, 2));
select pg_temp.as_user('owner');
select pg_temp.putx('inv_rex', public.create_invoice_with_details(pg_temp.fx('van'), (pg_temp.pp(pg_temp.fx('rex'))).customer_id,
  jsonb_build_array(
    jsonb_build_object('kind', 'event_ticket', 'event_ticket_option_id', pg_temp.fx('vip'), 'quantity', 1,
      'attendees', jsonb_build_array(jsonb_build_object('name', 'Rex Extraline', 'customer_id', (pg_temp.pp(pg_temp.fx('rex'))).customer_id))),
    jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.fx('save72'), 'quantity', 1, 'is_foc', true, 'foc_reason', 'Included with VIP · test'),
    jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.fx('three'), 'quantity', 1)),
  jsonb_build_object('business_date', public.sg_today(), 'manual_discount', 0)));
select public.record_invoice_payment(pg_temp.fx('inv_rex'), jsonb_build_array(jsonb_build_object(
  'payment_method_id', pg_temp.fx('bank'), 'amount', (select total_amount from invoices where id = pg_temp.fx('inv_rex')),
  'reference', 'REF xf12', 'payment_date', public.sg_today())), gen_random_uuid());
-- recorded as his website VIP order (a bank transfer a Manager invoiced)
with o as (insert into event_vip_orders(event_id, order_id, provider, status, unit_amount_cents, quantity, amount_total_cents, reference, paid_on)
           values (pg_temp.fx('ev'), pg_temp.bid('VIP', 'xf12'), 'bank', 'invoiced', 7200, 1, 7200, 'REF xf12', public.sg_today()) returning id)
insert into event_vip_order_people(order_ref, person_id, position, invoice_id, invoice_item_id)
select o.id, pg_temp.fx('rex'), 1, pg_temp.fx('inv_rex'), pg_temp.ticket(pg_temp.fx('inv_rex')) from o;
select pg_temp.as_user('staff');
select pg_temp.put('xf12_plan', public.invoice_action_plan(pg_temp.fx('inv_rex'), 'refund_partial',
  jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.ticket(pg_temp.fx('inv_rex')), 'quantity', 1)))::text);
select pg_temp.put('xf12_plan_other', public.invoice_action_plan(pg_temp.fx('inv_rex'), 'refund_partial',
  jsonb_build_array(jsonb_build_object('invoice_item_id',
    (select it.id from invoice_items it where it.invoice_id = pg_temp.fx('inv_rex') and it.line_kind = 'voucher' and not coalesce(it.is_foc, false)),
    'quantity', 1)))::text);
select pg_temp.as_user('owner');
select pg_temp.put('xf12_ref', pg_temp.err(format('select public.refund_invoice_recorded(%L, %L, %L, %L, %L, %L)', pg_temp.fx('inv_rex'),
  jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.ticket(pg_temp.fx('inv_rex')), 'amount', 72)),
  jsonb_build_array(jsonb_build_object('payment_id', pg_temp.payment(pg_temp.fx('inv_rex')), 'amount', 72)), '[]', 'VIP ticket refunded', gen_random_uuid())));
select pg_temp.check((select total_amount from invoices where id = pg_temp.fx('inv_rex')) = 288
    and (pg_temp.tx('xf12_plan')::jsonb)->'summary' @> jsonb_build_array('Take back the unused HT436 $72 discount Voucher that came with VIP from Rex Extraline.')
    and pg_temp.tx('xf12_plan') !~ '3-in-1 Vouchers that came with VIP|3-in-1 Vouchers, included with VIP|vip_voucher_used'
    and (pg_temp.tx('xf12_plan')::jsonb)->>'refund_amount' = '72.00'
    and (pg_temp.tx('xf12_plan_other')::jsonb)->>'refund_amount' = '216.00'
    and pg_temp.tx('xf12_plan_other') !~ 'came with VIP|included with VIP|vip_voucher_used'
    and pg_temp.tx('xf12_ref') = 'ok'
    and (select status::text from invoices where id = pg_temp.fx('inv_rex')) = 'paid'
    and pg_temp.vstat(pg_temp.fx('inv_rex')) = '{"save72": "revoked", "three": "held"}'::jsonb
    and pg_temp.audits(pg_temp.fx('inv_rex'), 'vip_voucher_taken_back') = 1,
  'XF12 Rex''s VIP ticket refunded in full (a paid 3-in-1 on the same invoice): only the voucher included with VIP is taken back; a part refund of the paid 3-in-1 alone takes no VIP voucher back: '
  || left(pg_temp.tx('xf12_plan'), 400) || ' | ' || left(pg_temp.tx('xf12_plan_other'), 400));
select pg_temp.checkout('live', 'xf12s', array[pg_temp.tx('tok:sol')]);
select pg_temp.put('xf12_sol_paid', pg_temp.paid('live', 'xf12s', array[pg_temp.tx('tok:sol')], 7200)::text);
select pg_temp.putx('inv_sol', (select i.id from pg_temp.vinvoices('xf12s') i));
create function pg_temp.undone_deleted_refund(inv uuid) returns text language plpgsql as
$$begin
  begin
    update invoices set deleted_at = now() where id = inv;
    update invoices set status = 'refunded', paid_amount = 0 where id = inv;
    raise exception 'UNDONE %', pg_temp.vstat(inv);
  exception when others then return sqlerrm;
  end;
end$$;
select pg_temp.put('xf12_sol', pg_temp.undone_deleted_refund(pg_temp.fx('inv_sol')));
select pg_temp.check(pg_temp.fx('inv_sol') is not null
    and pg_temp.tx('xf12_sol') = 'UNDONE {"three": "held", "save72": "held"}',
  'XF12 a deleted VIP invoice marked refunded takes nothing back: ' || pg_temp.tx('xf12_sol') || ' | ' || pg_temp.tx('xf12_sol_paid'));

-- ═════ XR The owner's answers, round 3 (20 Oct 2026) ═════
-- 1. A VIP voucher (SAVE72, 3-in-1) the customer already used on a LATER invoice that is not cancelled or deleted: no
--    automatic full refund of the VIP on any path, naming that invoice; the guided Refund in full (or Cancel) carries an
--    Owner's or Manager's override vip_voucher_used_later instead of a blocker (the owner, 21 Oct 2026: they may allow it
--    with a reason; staff cannot; section XO); the Finance panel refuses it; an Owner or Manager records a part refund by
--    hand. 2. A VIP sold at the counter (the VIP ticket with SAVE72 and/or 3-in-1 as free lines) follows the same rules.
--    3. Refunded or cancelled, reopened and paid again, then refunded again: nothing is "used".
select pg_temp.as_user('owner');
do $$ declare p uuid; v uuid; begin
  insert into products(name, sku, product_type) values ('HT436 Massage Mat', 'HT436-MM-' || pg_temp.tx('sfx'), 'own') returning id into p;
  insert into store_product_prices(store_id, product_id, selling_price) values (pg_temp.fx('van'), p, 100);
  insert into store_inventory(store_id, product_id, current_qty) values (pg_temp.fx('van'), p, 20);
  insert into fx values ('mat', p);
  -- a free voucher that is not one of the VIP vouchers
  insert into vouchers(name, code, voucher_kind, qty_type, selling_price, is_active)
  values ('HT436 Welcome Voucher', 'HT436-WEL' || pg_temp.tx('sfx'), 'normal', 'unlimited', 30, true) returning id into v;
  insert into voucher_store_prices(voucher_id, store_id, selling_price, available_at_store) values (v, pg_temp.fx('van'), 30, true);
  insert into fx values ('welcome', v);
end $$;
-- An invoice of the mat with SAVE72 as the invoice's discount voucher ('invoice') or as the line's voucher ('line').
create function pg_temp.save72_invoice(cust uuid, how text) returns uuid language sql as
$$ select public.create_invoice_with_details(pg_temp.fx('van'), cust,
     jsonb_build_array(jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('mat'), 'quantity', 1)
                       || case when how = 'line' then jsonb_build_object('line_voucher_id', pg_temp.fx('save72')) else '{}'::jsonb end),
     jsonb_build_object('business_date', public.sg_today(), 'manual_discount', 0)
       || case when how = 'invoice' then jsonb_build_object('discount_voucher_id', pg_temp.fx('save72')) else '{}'::jsonb end) $$;
create function pg_temp.ino(inv uuid) returns text language sql as $$ select invoice_no from invoices where id = inv $$;
-- The override's and the trigger's words.
-- (A discount with that voucher kind was given; whether it was the VIP's own SAVE72 is not known: the owner's rule reads the invoices.)
create function pg_temp.later_plan_msg(holder text, voucher text, later uuid, vip uuid) returns text language sql as
$$ select 'A discount with the ' || voucher || ' was given to ' || holder || ' on ' || pg_temp.ino(later) || ', an invoice made after this VIP invoice ('
          || pg_temp.ino(vip) || '), so the VIP ticket is not refunded in full automatically. An Owner or Manager may allow the full refund, '
          || 'giving a reason (it is recorded); or refunds less, as a part refund in the Finance panel, less than the ticket (the customer then stays '
          || 'VIP and keeps the unused VIP vouchers).' $$;
create function pg_temp.later_err_msg(holder text, voucher text, later uuid, vip uuid) returns text language sql as
$$ select 'A discount with the ' || voucher || ' was given to ' || holder || ' on ' || pg_temp.ino(later) || ', an invoice made after the VIP invoice '
          || pg_temp.ino(vip) || ', so the VIP ticket is not refunded in full here. Use Refund in full on the invoice: an Owner or Manager can allow it '
          || 'there with a reason. Or record a part refund, less than the ticket (the customer stays VIP and keeps the unused VIP vouchers). Nothing was recorded.' $$;
-- The same, when the invoice was cancelled and the money it holds is being paid back.
create function pg_temp.later_cancelled_msg(holder text, voucher text, later uuid, vip uuid) returns text language sql as
$$ select 'A discount with the ' || voucher || ' was given to ' || holder || ' on ' || pg_temp.ino(later) || ', an invoice made after the VIP invoice '
          || pg_temp.ino(vip) || ' and before it was cancelled, so the money it holds is not all paid back here: it was cancelled without an '
          || 'Owner''s or Manager''s override for that. Record a part refund, less than it holds; or an Owner or Manager reopens the invoice '
          || 'and cancels it again with the guided Cancel. Nothing was recorded.' $$;
-- The VIP vouchers of an invoice (its free voucher lines' benefits, replacements included), by status.
create function pg_temp.vcount(inv uuid, st text) returns bigint language sql as
$$ select count(*) from customer_reward_vouchers v
    where v.status = st and v.id in (select b.reward_voucher_id from invoice_benefit_values b join invoice_items it on it.id = b.invoice_item_id
                                      where b.invoice_id = inv and it.line_kind = 'voucher' and coalesce(it.is_foc, false)) $$;
create function pg_temp.panel_refund(inv uuid, amount numeric, why text) returns text language sql as
$$ select pg_temp.err(format('select public.refund_invoice_recorded(%L, %L, %L, %L, %L, %L)', inv,
     jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.ticket(inv), 'amount', amount)),
     jsonb_build_array(jsonb_build_object('payment_id', coalesce(
       (select p.id from invoice_payments p where p.invoice_id = inv and public.invoice_payment_remaining(p.id) >= amount
         order by p.created_at desc, p.id limit 1), pg_temp.payment(inv)), 'amount', amount)), '[]', why, gen_random_uuid())) $$;
create function pg_temp.blockers(plan text) returns jsonb language sql as
$$ select coalesce((plan::jsonb)->'blockers', 'null'::jsonb) $$;
-- What a call returns, or its error.
create function pg_temp.try(q text) returns text language plpgsql as
$$declare v text; begin execute q into v; return v; exception when others then return sqlerrm; end$$;
create function pg_temp.last_vip_audit(inv uuid) returns jsonb language sql as
$$ select a.new_data from audit_logs a where a.record_id = inv and a.action = 'vip_refund_vouchers' order by a.created_at desc, a.id desc limit 1 $$;
-- The later-use override in a plan (the owner, 21 Oct 2026), and that the plan is exactly: not blocked, the override with
-- its words, the line "Owner/Manager override required: ..." among what it does.
create function pg_temp.later_ov(plan text) returns jsonb language sql as
$$ select o from jsonb_array_elements(coalesce((plan::jsonb)->'overrides_required', '[]'::jsonb)) o where o->>'code' = 'vip_voucher_used_later' $$;
create function pg_temp.later_ov_is(plan text, holder text, voucher text, later uuid, vip uuid) returns boolean language sql as
$$ select pg_temp.later_ov(plan) = jsonb_build_object('code', 'vip_voucher_used_later', 'invoice_no', pg_temp.ino(later),
            'message', pg_temp.later_plan_msg(holder, voucher, later, vip))
      and (select count(*) from jsonb_array_elements((plan::jsonb)->'overrides_required') o where o->>'code' = 'vip_voucher_used_later') = 1
      and (plan::jsonb)->>'blocked' = 'false' and pg_temp.blockers(plan) = '[]'::jsonb
      and (plan::jsonb)->'summary' ? ('Owner/Manager override required: ' || pg_temp.later_plan_msg(holder, voucher, later, vip)) $$;

select pg_temp.put('xr_r', pg_temp.register('live', 'xr', jsonb_build_array(
  pg_temp.person(1, 'Lou', 'Laterused', pg_temp.ph(133), pg_temp.mail('xr-lou'), array[pg_temp.d(7)], true),
  pg_temp.person(2, 'Moe', 'Approvedlater', pg_temp.ph(134), pg_temp.mail('xr-moe'), array[pg_temp.d(7)], true),
  pg_temp.person(3, 'Rae', 'Reopenpanel', pg_temp.ph(135), pg_temp.mail('xr-rae'), array[pg_temp.d(8)], true),
  pg_temp.person(4, 'Sam', 'Reopenguided', pg_temp.ph(136), pg_temp.mail('xr-sam'), array[pg_temp.d(8)], true)))::text);
select pg_temp.putx(k, pg_temp.pid(pg_temp.tx('xr_r')::jsonb, n)) from (values ('lou', 1), ('moe', 2), ('rae', 3), ('sam', 4)) x(k, n);
select pg_temp.put('tok:' || k, pg_temp.tok(pg_temp.tx('xr_r')::jsonb, n)) from (values ('lou', 1), ('moe', 2), ('rae', 3), ('sam', 4)) x(k, n);
select pg_temp.checkout('live', 'xr', array[pg_temp.tx('tok:lou'), pg_temp.tx('tok:moe'), pg_temp.tx('tok:rae'), pg_temp.tx('tok:sam')]);
select pg_temp.put('xr_p', pg_temp.paid('live', 'xr', array[pg_temp.tx('tok:lou'), pg_temp.tx('tok:moe'), pg_temp.tx('tok:rae'), pg_temp.tx('tok:sam')], 28800)::text);
select pg_temp.putx('inv_' || k, (select i.id from pg_temp.vinvoices('xr') i where i.customer_id = (pg_temp.pp(pg_temp.fx(k))).customer_id))
  from unnest(array['lou', 'moe', 'rae', 'sam']) k;
select pg_temp.putx('c_' || k, (pg_temp.pp(pg_temp.fx(k))).customer_id) from unnest(array['lou', 'moe', 'rae', 'sam']) k;
select pg_temp.check((pg_temp.tx('xr_p')::jsonb)->>'status' = 'invoiced'
    and (select count(*) from pg_temp.vinvoices('xr') i where i.status = 'paid') = 4
    and (select bool_and(pg_temp.vcount(i.id, 'held') = 2) from pg_temp.vinvoices('xr') i),
  'XR0 four website VIPs paid, each holding both VIP vouchers: ' || pg_temp.tx('xr_p'));

-- XR1 Lou. Not counted: an invoice of hers made before the VIP invoice, a later one deleted, a later one cancelled,
-- another customer's later one (each with SAVE72 as a discount).
select pg_temp.as_user('owner');
-- (made two days before: its creation time cannot be changed afterwards, so the row is written as it would be)
insert into invoices(invoice_no, store_id, customer_id, created_by, status, subtotal, discount_total, total_amount, paid_amount,
                     discount_voucher_id, business_date, created_at)
values ('HT436-B-' || pg_temp.tx('sfx'), pg_temp.fx('van'), pg_temp.fx('c_lou'), pg_temp.fx('owner'), 'unpaid', 100, 72, 28, 0,
        pg_temp.fx('save72'), public.sg_today() - 2, now() - interval '2 days');
select pg_temp.putx('xr1_before', (select id from invoices where invoice_no = 'HT436-B-' || pg_temp.tx('sfx')));
select pg_temp.putx('xr1_deleted', pg_temp.save72_invoice(pg_temp.fx('c_lou'), 'line'));
select public.delete_invoice(pg_temp.fx('xr1_deleted'), 'Made by mistake');
select pg_temp.putx('xr1_cancelled', pg_temp.save72_invoice(pg_temp.fx('c_lou'), 'invoice'));
select public.cancel_invoice_recorded(pg_temp.fx('xr1_cancelled'), 'Made by mistake', gen_random_uuid());
select pg_temp.save72_invoice(pg_temp.fx('c_exact'), 'invoice');
select pg_temp.as_user('staff');
select pg_temp.put('xr1_plan0', public.invoice_action_plan(pg_temp.fx('inv_lou'), 'refund_full', '[]')::text);
select pg_temp.check((select created_at < (select created_at from invoices where id = pg_temp.fx('inv_lou')) from invoices where id = pg_temp.fx('xr1_before'))
    and (select deleted_at is not null from invoices where id = pg_temp.fx('xr1_deleted'))
    and (select status::text from invoices where id = pg_temp.fx('xr1_cancelled')) = 'cancelled'
    and (select discount_voucher_id from invoices where id = pg_temp.fx('xr1_before')) = pg_temp.fx('save72')
    and (pg_temp.tx('xr1_plan0')::jsonb)->>'blocked' = 'false'
    and pg_temp.blockers(pg_temp.tx('xr1_plan0')) = '[]'::jsonb and pg_temp.later_ov(pg_temp.tx('xr1_plan0')) is null
    and (pg_temp.tx('xr1_plan0')::jsonb)->'summary' @> jsonb_build_array('Take back the unused HT436 $72 discount Voucher that came with VIP from Lou Laterused.'),
  'XR1 SAVE72 on an invoice before the VIP invoice, on a deleted or a cancelled later one, or on another customer''s does not stop Refund in full: ' || pg_temp.tx('xr1_plan0'));
-- Counted: a later invoice of hers with SAVE72 as its discount voucher (S$72 off; she still holds the VIP's SAVE72).
select pg_temp.as_user('owner');
select pg_temp.putx('xr1_later', pg_temp.save72_invoice(pg_temp.fx('c_lou'), 'invoice'));
select pg_temp.as_user('staff');
select pg_temp.put('xr1_plan', public.invoice_action_plan(pg_temp.fx('inv_lou'), 'refund_full', '[]')::text);
select pg_temp.put('xr1_plan_part', public.invoice_action_plan(pg_temp.fx('inv_lou'), 'refund_partial',
  jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.ticket(pg_temp.fx('inv_lou')), 'quantity', 1)))::text);
select pg_temp.put('xr1_req', public.request_invoice_action_v2(pg_temp.fx('inv_lou'), 'refund_full', '[]', 'Cannot come', null, gen_random_uuid())::text);
select pg_temp.put('xr1_staff_app', pg_temp.err(format('select public.resolve_invoice_action_v2(%L, true, %L, %L, %L, null, false)',
  pg_temp.tx('xr1_req')::jsonb->>'request_id', 'Refunded', pg_temp.tx('xr1_req')::jsonb->'plan'->>'plan_hash',
  jsonb_build_array(jsonb_build_object('code', 'vip_voucher_used_later', 'reason', 'Staff try')))));
select pg_temp.as_user('manager');
select pg_temp.put('xr1_noreason', pg_temp.err(format('select public.resolve_invoice_action_v2(%L, true, %L, %L, %L, null, false)',
  pg_temp.tx('xr1_req')::jsonb->>'request_id', 'Refunded', pg_temp.tx('xr1_req')::jsonb->'plan'->>'plan_hash',
  jsonb_build_array(jsonb_build_object('code', 'vip_voucher_used_later', 'reason', '  ')))));
select pg_temp.put('xr1_reject', pg_temp.err(format('select public.resolve_invoice_action_v2(%L, false, %L)',
  pg_temp.tx('xr1_req')::jsonb->>'request_id', 'Decided by hand in the Finance panel')));
select pg_temp.check((select total_amount from invoices where id = pg_temp.fx('xr1_later')) = 28
    and pg_temp.later_ov_is(pg_temp.tx('xr1_plan'), 'Lou Laterused', 'HT436 $72 discount Voucher', pg_temp.fx('xr1_later'), pg_temp.fx('inv_lou'))
    and pg_temp.later_ov(pg_temp.tx('xr1_plan_part')) = pg_temp.later_ov(pg_temp.tx('xr1_plan'))
    and (pg_temp.tx('xr1_req')::jsonb)->>'status' = 'pending'
    and pg_temp.later_ov((pg_temp.tx('xr1_req')::jsonb->'plan')::text) = pg_temp.later_ov(pg_temp.tx('xr1_plan'))
    and pg_temp.tx('xr1_staff_app') = 'Only an Owner or Manager can approve or reject an invoice request'
    and pg_temp.tx('xr1_noreason') = 'An Owner/Manager override reason is required for: vip_voucher_used_later'
    and pg_temp.tx('xr1_reject') = 'ok'
    and (select status::text from approval_requests where id = (pg_temp.tx('xr1_req')::jsonb->>'request_id')::uuid) = 'rejected'
    and (select status::text from invoices where id = pg_temp.fx('inv_lou')) = 'paid'
    and not exists (select 1 from invoice_refunds where invoice_id = pg_temp.fx('inv_lou'))
    and pg_temp.vcount(pg_temp.fx('inv_lou'), 'held') = 2
    and not exists (select 1 from audit_logs a where a.record_id = pg_temp.fx('inv_lou') and a.action = 'vip_refund_used_later_allowed'),
  'XR1 SAVE72 used on a later invoice: Refund in full (and a part refund that pays the ticket back in full) is not automatic: the plan names that invoice as an Owner''s or Manager''s override (the owner, 21 Oct 2026); staff may ask but cannot approve, and no approval goes without a reason; nothing changes: ' || pg_temp.tx('xr1_noreason'));
select pg_temp.as_user('owner');
select pg_temp.put('xr1_full', pg_temp.panel_refund(pg_temp.fx('inv_lou'), 72, 'Refund in full'));
select pg_temp.check(pg_temp.tx('xr1_full') = pg_temp.later_err_msg('Lou Laterused', 'HT436 $72 discount Voucher', pg_temp.fx('xr1_later'), pg_temp.fx('inv_lou'))
    and (select status::text from invoices where id = pg_temp.fx('inv_lou')) = 'paid'
    and (select count(*) from invoice_refunds where invoice_id = pg_temp.fx('inv_lou')) = 0
    and pg_temp.vcount(pg_temp.fx('inv_lou'), 'held') = 2
    and public.event_web_person_vip_state(pg_temp.fx('lou')) = 'paid',
  'XR1 the Finance panel''s refund in full is refused too, naming the later invoice, and nothing changes: ' || pg_temp.tx('xr1_full'));
select pg_temp.put('xr1_part_owner', pg_temp.panel_refund(pg_temp.fx('inv_lou'), 30, 'The Owner agreed S$30'));
select pg_temp.as_user('manager');
select pg_temp.put('xr1_part_manager', pg_temp.panel_refund(pg_temp.fx('inv_lou'), 10, 'And S$10 more'));
select pg_temp.put('xr1_rest', pg_temp.panel_refund(pg_temp.fx('inv_lou'), 32, 'The rest'));
select pg_temp.as_user('staff');
select pg_temp.put('xr1_plan2', public.invoice_action_plan(pg_temp.fx('inv_lou'), 'refund_full', '[]')::text);
select pg_temp.check(pg_temp.tx('xr1_part_owner') = 'ok' and pg_temp.tx('xr1_part_manager') = 'ok'
    and pg_temp.tx('xr1_rest') = pg_temp.later_err_msg('Lou Laterused', 'HT436 $72 discount Voucher', pg_temp.fx('xr1_later'), pg_temp.fx('inv_lou'))
    and (select status::text from invoices where id = pg_temp.fx('inv_lou')) = 'paid'
    and (select coalesce(sum(amount), 0) from invoice_refunds where invoice_id = pg_temp.fx('inv_lou')) = 40
    and pg_temp.vcount(pg_temp.fx('inv_lou'), 'held') = 2
    and public.event_web_person_vip_state(pg_temp.fx('lou')) = 'paid'
    and pg_temp.later_ov(pg_temp.tx('xr1_plan2')) is not null and (pg_temp.tx('xr1_plan2')::jsonb)->>'blocked' = 'false'
    and (pg_temp.tx('xr1_plan2')::jsonb)->>'refund_amount' = '32.00',
  'XR1 an Owner and a Manager still record part refunds by hand (S$30, S$10; still VIP, vouchers held); the rest is refused: ' || pg_temp.tx('xr1_rest'));

-- XR2 Moe: Refund in full asked for first; then SAVE72 used as a line's voucher on a later invoice: the approval shows the
-- revised plan with the override, refused without a reason, and nothing changes. Once that invoice is cancelled, the same
-- approval goes through.
select pg_temp.as_user('staff');
select pg_temp.put('xr2_req', public.request_invoice_action_v2(pg_temp.fx('inv_moe'), 'refund_full', '[]', 'Cannot come', null, gen_random_uuid())::text);
select pg_temp.as_user('owner');
select pg_temp.putx('xr2_later', pg_temp.save72_invoice(pg_temp.fx('c_moe'), 'line'));
select pg_temp.as_user('manager');
select pg_temp.put('xr2_app', pg_temp.try(format('select public.resolve_invoice_action_v2(%L, true, %L, %L, %L, null, false)::text',
  (pg_temp.tx('xr2_req')::jsonb->>'request_id'), 'Refunded', pg_temp.tx('xr2_req')::jsonb->'plan'->>'plan_hash', '[]')));
select pg_temp.put('xr2_app2', pg_temp.err(format('select public.resolve_invoice_action_v2(%L, true, %L, %L, %L, null, false)',
  (pg_temp.tx('xr2_req')::jsonb->>'request_id'), 'Refunded', pg_temp.tx('xr2_app')::jsonb->'revised_plan'->>'plan_hash', '[]')));
select pg_temp.check((pg_temp.tx('xr2_req')::jsonb)->>'status' = 'pending'
    and (select line_voucher_id from invoice_items where invoice_id = pg_temp.fx('xr2_later')) = pg_temp.fx('save72')
    and (pg_temp.tx('xr2_app')::jsonb)->>'confirmation_required' = 'true'
    and pg_temp.later_ov_is((pg_temp.tx('xr2_app')::jsonb->'revised_plan')::text, 'Moe Approvedlater', 'HT436 $72 discount Voucher',
                            pg_temp.fx('xr2_later'), pg_temp.fx('inv_moe'))
    and pg_temp.tx('xr2_app2') = 'An Owner/Manager override reason is required for: vip_voucher_used_later'
    and (select status from approval_requests where id = (pg_temp.tx('xr2_req')::jsonb->>'request_id')::uuid) = 'pending'
    and (select status::text from invoices where id = pg_temp.fx('inv_moe')) = 'paid'
    and pg_temp.vcount(pg_temp.fx('inv_moe'), 'held') = 2,
  'XR2 SAVE72 used as a line voucher after the request: its approval first shows the revised plan with the override, and without a reason it is refused; nothing changes: ' || left(pg_temp.tx('xr2_app'), 160));
select pg_temp.as_user('owner');
select public.cancel_invoice_recorded(pg_temp.fx('xr2_later'), 'Made by mistake', gen_random_uuid());
select pg_temp.as_user('manager');
select pg_temp.put('xr2_res', public.resolve_invoice_action_v2((pg_temp.tx('xr2_req')::jsonb->>'request_id')::uuid, true, 'Refunded',
  pg_temp.tx('xr2_req')::jsonb->'plan'->>'plan_hash', '[]', null, false)::text);
select pg_temp.check((pg_temp.tx('xr2_res')::jsonb)->>'status' = 'approved'
    and (select status::text from invoices where id = pg_temp.fx('inv_moe')) = 'refunded'
    and pg_temp.vcount(pg_temp.fx('inv_moe'), 'revoked') = 2
    and public.event_web_person_vip_state(pg_temp.fx('moe')) = 'refunded',
  'XR2 the later invoice cancelled: the same approval goes through and both vouchers are taken back');

-- XR3 VIPs sold at the counter (staff add SAVE72 and the 3-in-1 as free lines): the same rules as a website VIP.
-- Cy: Refund in full takes both back (no website record is involved). Dee: the Finance panel's refund in full takes both back.
-- Eli: SAVE72 used on a later invoice: refused on every path; a part refund still goes. Fay: her 3-in-1 recorded used: the
-- Finance panel refuses, Refund in full names it. Gus: a free voucher that is not a VIP voucher stays with him. Hana: the VIP
-- ticket with only that voucher is not a VIP sale.
select pg_temp.as_user('owner');
insert into customers(full_name, phone) values
  ('Cy Counterfull', '+61491570737'), ('Dee Counterpanel', '+61491572983'), ('Eli Counterlater', '+61491573770'),
  ('Fay Counterused', pg_temp.ph(162)), ('Gus Counterother', pg_temp.ph(163)), ('Hana Counterplain', pg_temp.ph(164));
select pg_temp.putx(k, (select id from customers where full_name = n and deleted_at is null order by created_at desc limit 1))
  from (values ('cy', 'Cy Counterfull'), ('dee', 'Dee Counterpanel'), ('eli', 'Eli Counterlater'), ('fay', 'Fay Counterused'),
               ('gus', 'Gus Counterother'), ('hana', 'Hana Counterplain')) x(k, n);
create function pg_temp.counter_vip(cust uuid, vouchers uuid[]) returns uuid language plpgsql as
$$declare v uuid; x uuid; begin
  v := public.create_invoice_with_details(pg_temp.fx('van'), cust,
    jsonb_build_array(jsonb_build_object('kind', 'event_ticket', 'event_ticket_option_id', pg_temp.fx('vip'), 'quantity', 1,
      'attendees', jsonb_build_array(jsonb_build_object('name', (select full_name from customers where id = cust), 'customer_id', cust))))
    || coalesce((select jsonb_agg(jsonb_build_object('kind', 'voucher', 'voucher_id', u, 'quantity', 1, 'is_foc', true,
                                                     'foc_reason', 'Included with VIP · counter')) from unnest(vouchers) u), '[]'::jsonb),
    jsonb_build_object('business_date', public.sg_today(), 'manual_discount', 0));
  perform public.record_invoice_payment(v, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('bank'),
    'amount', (select total_amount from invoices where id = v), 'reference', 'Counter VIP', 'payment_date', public.sg_today())), gen_random_uuid());
  return v;
end$$;
select pg_temp.putx('inv_' || k, pg_temp.counter_vip(pg_temp.fx(k), array[pg_temp.fx('save72'), pg_temp.fx('three')]))
  from unnest(array['cy', 'dee', 'eli', 'fay']) k;
select pg_temp.putx('inv_gus', pg_temp.counter_vip(pg_temp.fx('gus'), array[pg_temp.fx('save72'), pg_temp.fx('welcome')]));
select pg_temp.putx('inv_hana', pg_temp.counter_vip(pg_temp.fx('hana'), array[pg_temp.fx('welcome')]));
select pg_temp.check((select bool_and(i.status::text = 'paid' and i.total_amount = 72) from invoices i
                       where i.id in (pg_temp.fx('inv_cy'), pg_temp.fx('inv_dee'), pg_temp.fx('inv_eli'), pg_temp.fx('inv_fay'), pg_temp.fx('inv_gus'), pg_temp.fx('inv_hana')))
    and pg_temp.vcount(pg_temp.fx('inv_cy'), 'held') = 2 and pg_temp.vcount(pg_temp.fx('inv_gus'), 'held') = 2 and pg_temp.vcount(pg_temp.fx('inv_hana'), 'held') = 1
    and not exists (select 1 from event_vip_order_people op where op.invoice_id in (pg_temp.fx('inv_cy'), pg_temp.fx('inv_dee'), pg_temp.fx('inv_eli'), pg_temp.fx('inv_fay'))),
  'XR3 six counter invoices with the VIP ticket and free vouchers, paid by bank transfer, the vouchers on each customer''s account');
select pg_temp.as_user('staff');
select pg_temp.put('xr3_cy_plan', public.invoice_action_plan(pg_temp.fx('inv_cy'), 'refund_full', '[]')::text);
select pg_temp.put('xr3_cy_req', public.request_invoice_action_v2(pg_temp.fx('inv_cy'), 'refund_full', '[]', 'Cannot come', null, gen_random_uuid())::text);
select pg_temp.as_user('manager');
select pg_temp.put('xr3_cy_res', public.resolve_invoice_action_v2((pg_temp.tx('xr3_cy_req')::jsonb->>'request_id')::uuid, true, 'Refunded',
  pg_temp.tx('xr3_cy_req')::jsonb->'plan'->>'plan_hash', '[]', null, false)::text);
select pg_temp.check((pg_temp.tx('xr3_cy_plan')::jsonb)->'summary' @> jsonb_build_array(
        'Take back the unused HT436 $72 discount Voucher that came with VIP from Cy Counterfull.',
        'Take back the unused HT436 3-in-1 Vouchers that came with VIP from Cy Counterfull.')
    and jsonb_array_length((pg_temp.tx('xr3_cy_plan')::jsonb)->'effects'->'benefits') = 2
    and (pg_temp.tx('xr3_cy_plan')::jsonb)->>'refund_amount' = '72.00'
    and coalesce((pg_temp.tx('xr3_cy_plan')::jsonb)->>'requires_override', 'false') = 'false'
    and (pg_temp.tx('xr3_cy_res')::jsonb)->>'status' = 'approved'
    and (select status::text from invoices where id = pg_temp.fx('inv_cy')) = 'refunded'
    and pg_temp.vcount(pg_temp.fx('inv_cy'), 'revoked') = 2
    and pg_temp.audits(pg_temp.fx('inv_cy'), 'vip_voucher_taken_back') = 2
    and (pg_temp.last_vip_audit(pg_temp.fx('inv_cy')))->'used_kept' = '[]'::jsonb
    and not exists (select 1 from event_registration_people p where p.customer_id = pg_temp.fx('cy')),
  'XR3 Cy (counter VIP): Refund in full says first that both vouchers are taken back, and takes them back; no website record is involved: ' || left(pg_temp.tx('xr3_cy_plan'), 500));
select pg_temp.as_user('owner');
select pg_temp.put('xr3_dee', pg_temp.panel_refund(pg_temp.fx('inv_dee'), 72, 'Refund in full'));
select pg_temp.check(pg_temp.tx('xr3_dee') = 'ok'
    and (select status::text from invoices where id = pg_temp.fx('inv_dee')) = 'refunded'
    and pg_temp.vcount(pg_temp.fx('inv_dee'), 'revoked') = 2 and pg_temp.vcount(pg_temp.fx('inv_dee'), 'held') = 0,
  'XR3 Dee (counter VIP) refunded in full from the Finance panel: both vouchers taken back: ' || pg_temp.tx('xr3_dee'));
select pg_temp.putx('xr3_eli_later', pg_temp.save72_invoice(pg_temp.fx('eli'), 'line'));
select pg_temp.as_user('staff');
select pg_temp.put('xr3_eli_plan', public.invoice_action_plan(pg_temp.fx('inv_eli'), 'refund_full', '[]')::text);
select pg_temp.put('xr3_eli_req', pg_temp.err(format('select public.request_invoice_action_v2(%L, %L, %L, %L, null, %L)',
  pg_temp.fx('inv_eli'), 'refund_full', '[]', 'Cannot come', gen_random_uuid())));
select pg_temp.as_user('owner');
select pg_temp.put('xr3_eli_full', pg_temp.panel_refund(pg_temp.fx('inv_eli'), 72, 'Refund in full'));
select pg_temp.as_user('manager');
select pg_temp.put('xr3_eli_part', pg_temp.panel_refund(pg_temp.fx('inv_eli'), 36, 'Half, agreed'));
select pg_temp.check(pg_temp.later_ov_is(pg_temp.tx('xr3_eli_plan'), 'Eli Counterlater', 'HT436 $72 discount Voucher', pg_temp.fx('xr3_eli_later'), pg_temp.fx('inv_eli'))
    and pg_temp.tx('xr3_eli_req') = 'ok'
    and pg_temp.tx('xr3_eli_full') = pg_temp.later_err_msg('Eli Counterlater', 'HT436 $72 discount Voucher', pg_temp.fx('xr3_eli_later'), pg_temp.fx('inv_eli'))
    and pg_temp.tx('xr3_eli_part') = 'ok'
    and (select status::text from invoices where id = pg_temp.fx('inv_eli')) = 'paid'
    and pg_temp.vcount(pg_temp.fx('inv_eli'), 'held') = 2,
  'XR3 Eli (counter VIP) used SAVE72 on a later invoice: Refund in full needs the override (staff''s request waits for it), the Finance panel''s refund in full is refused, naming it; a Manager''s part refund goes: ' || pg_temp.tx('xr3_eli_full'));
update customer_reward_vouchers set status = 'redeemed', redeemed_at = now()
 where voucher_id = pg_temp.fx('three') and id in (select b.reward_voucher_id from invoice_benefit_values b where b.invoice_id = pg_temp.fx('inv_fay'));
select pg_temp.as_user('owner');
select pg_temp.put('xr3_fay_full', pg_temp.panel_refund(pg_temp.fx('inv_fay'), 72, 'Refund in full'));
select pg_temp.as_user('staff');
select pg_temp.put('xr3_fay_plan', public.invoice_action_plan(pg_temp.fx('inv_fay'), 'refund_full', '[]')::text);
select pg_temp.check(pg_temp.tx('xr3_fay_full') = 'A voucher that came with VIP on ' || pg_temp.ino(pg_temp.fx('inv_fay'))
        || ' has already been used, so this refund is not recorded here. Use Refund in full on the invoice: it says which voucher first and asks for a reason.'
    and exists (select 1 from jsonb_array_elements((pg_temp.tx('xr3_fay_plan')::jsonb)->'overrides_required') o
                 where o->>'code' = 'vip_voucher_used' and o->>'message' like 'Fay Counterused has already used the HT436 3-in-1 Vouchers that came with VIP (%')
    and (pg_temp.tx('xr3_fay_plan')::jsonb)->>'blocked' = 'false'
    and (select status::text from invoices where id = pg_temp.fx('inv_fay')) = 'paid',
  'XR3 Fay (counter VIP) with her 3-in-1 recorded used: the Finance panel refuses; Refund in full names it and asks for a reason: ' || pg_temp.tx('xr3_fay_full'));
select pg_temp.as_user('staff');
select pg_temp.put('xr3_gus_plan', public.invoice_action_plan(pg_temp.fx('inv_gus'), 'refund_full', '[]')::text);
select pg_temp.put('xr3_hana_plan', public.invoice_action_plan(pg_temp.fx('inv_hana'), 'refund_full', '[]')::text);
select pg_temp.as_user('owner');
select pg_temp.put('xr3_gus', pg_temp.panel_refund(pg_temp.fx('inv_gus'), 72, 'Refund in full'));
select pg_temp.put('xr3_hana', pg_temp.panel_refund(pg_temp.fx('inv_hana'), 72, 'Refund in full'));
select pg_temp.check(pg_temp.tx('xr3_gus') = 'ok' and pg_temp.tx('xr3_hana') = 'ok'
    and (pg_temp.tx('xr3_gus_plan')::jsonb)->'summary' @> jsonb_build_array('Take back the unused HT436 $72 discount Voucher that came with VIP from Gus Counterother.')
    and pg_temp.tx('xr3_gus_plan') !~ 'Welcome Voucher that came with VIP|Welcome Voucher, included with VIP'
    and pg_temp.tx('xr3_hana_plan') !~ 'came with VIP|included with VIP'
    and (select v.status from customer_reward_vouchers v where v.customer_id = pg_temp.fx('gus') and v.voucher_id = pg_temp.fx('save72')) = 'revoked'
    and (select v.status from customer_reward_vouchers v where v.customer_id = pg_temp.fx('gus') and v.voucher_id = pg_temp.fx('welcome')) = 'held'
    and (select v.status from customer_reward_vouchers v where v.customer_id = pg_temp.fx('hana') and v.voucher_id = pg_temp.fx('welcome')) = 'held'
    and pg_temp.audits(pg_temp.fx('inv_hana'), 'vip_refund_vouchers') = 0,
  'XR3 only the VIP vouchers are a counter VIP''s: Gus''s free Welcome voucher stays with him; Hana (VIP ticket, Welcome voucher only) is a normal refund');

-- XR4 refunded, reopened, paid again, refunded again (the confirmed bug): nothing reads as used.
-- Rae: the Finance panel both times. Sam: cancelled (its refund recorded), reopened, paid, then the guided Refund in full.
select pg_temp.as_user('owner');
select pg_temp.put('xr4_rae1', pg_temp.panel_refund(pg_temp.fx('inv_rae'), 72, 'Refund in full'));
select public.reopen_invoice(pg_temp.fx('inv_rae'), 'Refunded by mistake', gen_random_uuid());
select public.record_invoice_payment(pg_temp.fx('inv_rae'), jsonb_build_array(jsonb_build_object(
  'payment_method_id', pg_temp.fx('hitpay'), 'amount', 72, 'reference', 'Paid again', 'payment_date', public.sg_today())), gen_random_uuid());
select pg_temp.as_user('staff');
select pg_temp.put('xr4_rae_plan', public.invoice_action_plan(pg_temp.fx('inv_rae'), 'refund_full', '[]')::text);
select pg_temp.as_user('owner');
select pg_temp.put('xr4_rae2', pg_temp.panel_refund(pg_temp.fx('inv_rae'), 72, 'Refund in full again'));
select pg_temp.check(pg_temp.tx('xr4_rae1') = 'ok' and pg_temp.tx('xr4_rae2') = 'ok'
    and (select count(*) from invoice_reopen_vouchers q where q.invoice_id = pg_temp.fx('inv_rae') and q.applied_at is not null) = 2
    and pg_temp.tx('xr4_rae_plan') !~ 'vip_voucher_used|already used'
    and coalesce((pg_temp.tx('xr4_rae_plan')::jsonb)->>'requires_override', 'false') = 'false'
    and (pg_temp.tx('xr4_rae_plan')::jsonb)->'summary' @> jsonb_build_array(
        'Take back the unused HT436 $72 discount Voucher that came with VIP from Rae Reopenpanel.',
        'Take back the unused HT436 3-in-1 Vouchers that came with VIP from Rae Reopenpanel.')
    and (select status::text from invoices where id = pg_temp.fx('inv_rae')) = 'refunded'
    and pg_temp.vcount(pg_temp.fx('inv_rae'), 'held') = 0 and pg_temp.vcount(pg_temp.fx('inv_rae'), 'revoked') = 4
    and (pg_temp.last_vip_audit(pg_temp.fx('inv_rae')))->'used_kept' = '[]'::jsonb
    and jsonb_array_length((pg_temp.last_vip_audit(pg_temp.fx('inv_rae')))->'taken_back') = 2
    and public.event_web_person_vip_state(pg_temp.fx('rae')) = 'refunded',
  'XR4 Rae refunded, reopened, paid again: Refund in full names nothing used, the Finance panel''s second refund goes and takes the replacements back: ' || pg_temp.tx('xr4_rae2'));
select pg_temp.as_user('staff');
select pg_temp.put('xr4_sam_creq', public.request_invoice_action_v2(pg_temp.fx('inv_sam'), 'cancel', '[]', 'Wrong day', null, gen_random_uuid())::text);
select pg_temp.as_user('manager');
select public.resolve_invoice_action_v2((pg_temp.tx('xr4_sam_creq')::jsonb->>'request_id')::uuid, true, 'Cancelled',
  pg_temp.tx('xr4_sam_creq')::jsonb->'plan'->>'plan_hash', '[]', null, true);
select pg_temp.as_user('owner');
select public.reopen_invoice(pg_temp.fx('inv_sam'), 'Cancelled by mistake', gen_random_uuid());
select public.record_invoice_payment(pg_temp.fx('inv_sam'), jsonb_build_array(jsonb_build_object(
  'payment_method_id', pg_temp.fx('hitpay'), 'amount', 72, 'reference', 'Paid again', 'payment_date', public.sg_today())), gen_random_uuid());
select pg_temp.as_user('staff');
select pg_temp.put('xr4_sam_plan', public.invoice_action_plan(pg_temp.fx('inv_sam'), 'refund_full', '[]')::text);
select pg_temp.put('xr4_sam_req', public.request_invoice_action_v2(pg_temp.fx('inv_sam'), 'refund_full', '[]', 'Cannot come after all', null, gen_random_uuid())::text);
select pg_temp.as_user('manager');
select pg_temp.put('xr4_sam_res', pg_temp.try(format('select public.resolve_invoice_action_v2(%L, true, %L, %L, %L, null, false)::text',
  (pg_temp.tx('xr4_sam_req')::jsonb->>'request_id'), 'Refunded', pg_temp.tx('xr4_sam_req')::jsonb->'plan'->>'plan_hash', '[]')));
select pg_temp.check(pg_temp.tx('xr4_sam_res') like '{%'
    and (select count(*) from invoice_reopen_vouchers q where q.invoice_id = pg_temp.fx('inv_sam') and q.applied_at is not null) = 2
    and pg_temp.tx('xr4_sam_plan') !~ 'vip_voucher_used|already used'
    and (pg_temp.tx('xr4_sam_plan')::jsonb)->'summary' @> jsonb_build_array(
        'Take back the unused HT436 $72 discount Voucher that came with VIP from Sam Reopenguided.',
        'Take back the unused HT436 3-in-1 Vouchers that came with VIP from Sam Reopenguided.')
    and (pg_temp.tx('xr4_sam_res')::jsonb)->>'status' = 'approved'
    and (select status::text from invoices where id = pg_temp.fx('inv_sam')) = 'refunded'
    and pg_temp.vcount(pg_temp.fx('inv_sam'), 'held') = 0 and pg_temp.vcount(pg_temp.fx('inv_sam'), 'revoked') = 4
    and (pg_temp.last_vip_audit(pg_temp.fx('inv_sam')))->'used_kept' = '[]'::jsonb
    and public.event_web_person_vip_state(pg_temp.fx('sam')) = 'refunded',
  'XR4 Sam cancelled, reopened, paid again: the guided Refund in full names nothing used, needs no reason, and takes the replacements back: ' || pg_temp.tx('xr4_sam_res'));

-- XR5 HitPay's refund notice for the four (S$256 back there): covered once the app holds as much refunded, Lou's S$40 part
-- refund (by hand, her SAVE72 used later) counting with the three refunded invoices; S$288 is not covered.
select pg_temp.as_user('owner');
select pg_temp.put('xr5_n1', pg_temp.call('live', 'vip_refund', jsonb_build_object('refund', jsonb_build_object('order_id', pg_temp.bid('VIP', 'xr'),
  'payment_request_id', (pg_temp.vorder('xr')).hitpay_payment_request_id, 'payment_id', null, 'refunded_cents_total', 25600,
  'refunded_at', now(), 'livemode', true)))::text);
select pg_temp.as_user('manager');
select pg_temp.put('xr5_c1', (select o->>'refund_covered' from jsonb_array_elements(public.event_vip_orders_list(pg_temp.fx('ev'))->'orders') o
                               where o->>'order_id' = pg_temp.bid('VIP', 'xr')));
select pg_temp.put('xr5_n2', pg_temp.call('live', 'vip_refund', jsonb_build_object('refund', jsonb_build_object('order_id', pg_temp.bid('VIP', 'xr'),
  'payment_request_id', (pg_temp.vorder('xr')).hitpay_payment_request_id, 'payment_id', null, 'refunded_cents_total', 28800,
  'refunded_at', now(), 'livemode', true)))::text);
select pg_temp.put('xr5_c2', (select o->>'refund_covered' from jsonb_array_elements(public.event_vip_orders_list(pg_temp.fx('ev'))->'orders') o
                               where o->>'order_id' = pg_temp.bid('VIP', 'xr')));
select pg_temp.check((pg_temp.tx('xr5_n1')::jsonb)->>'status' = 'noted' and pg_temp.tx('xr5_c1') = 'true'
    and (pg_temp.tx('xr5_n2')::jsonb)->>'refunded_cents_total' = '28800' and pg_temp.tx('xr5_c2') = 'false',
  'XR5 HitPay''s S$256 refund is covered by three refunded invoices and Lou''s S$40 part refund; S$288 is not: ' || pg_temp.tx('xr5_n1'));

-- XR6 Cancel meets the later-use rule too (every path): with SAVE72 given on a later invoice, a Cancel that pays the VIP
-- back in full needs the override, asked for before that invoice (its approval shows the revised plan first, and needs the
-- reason) or after (the request carries it; an Owner approves it with a reason, section XO's rule); the Owner's direct
-- cancellation (nothing paid back) still goes, but recording all of its refund due is refused (a part goes). With nothing
-- given later, Cancel with its refund recorded is as before.
select pg_temp.as_user('owner');
insert into customers(full_name, phone) values
  ('Ada Cancelfirst', pg_temp.ph(170)), ('Ben Cancelafter', pg_temp.ph(171)), ('Cat Directcancel', pg_temp.ph(172)),
  ('Dan Cancelnone', pg_temp.ph(173));
select pg_temp.putx(k, (select id from customers where full_name = n and deleted_at is null order by created_at desc limit 1))
  from (values ('ada', 'Ada Cancelfirst'), ('ben', 'Ben Cancelafter'), ('cat', 'Cat Directcancel'), ('dan', 'Dan Cancelnone')) x(k, n);
select pg_temp.putx('inv_' || k, pg_temp.counter_vip(pg_temp.fx(k), array[pg_temp.fx('save72'), pg_temp.fx('three')]))
  from unnest(array['ada', 'ben', 'cat', 'dan']) k;
select pg_temp.as_user('staff');
select pg_temp.put('xr6_ada_req', public.request_invoice_action_v2(pg_temp.fx('inv_ada'), 'cancel', '[]', 'Wrong day', null, gen_random_uuid())::text);
select pg_temp.as_user('owner');
select pg_temp.putx('xr6_ada_later', pg_temp.save72_invoice(pg_temp.fx('ada'), 'invoice'));
select pg_temp.as_user('manager');
select pg_temp.put('xr6_ada_cplan', public.invoice_action_plan(pg_temp.fx('inv_ada'), 'cancel', '[]')::text);
select pg_temp.put('xr6_ada_res', pg_temp.try(format('select public.resolve_invoice_action_v2(%L, true, %L, %L, %L, null, true)::text',
  (pg_temp.tx('xr6_ada_req')::jsonb->>'request_id'), 'Cancelled', pg_temp.tx('xr6_ada_req')::jsonb->'plan'->>'plan_hash', '[]')));
select pg_temp.put('xr6_ada_res2', pg_temp.err(format('select public.resolve_invoice_action_v2(%L, true, %L, %L, %L, null, true)',
  (pg_temp.tx('xr6_ada_req')::jsonb->>'request_id'), 'Cancelled', pg_temp.tx('xr6_ada_res')::jsonb->'revised_plan'->>'plan_hash', '[]')));
select pg_temp.check((pg_temp.tx('xr6_ada_req')::jsonb)->>'status' = 'pending'
    and pg_temp.later_ov_is(pg_temp.tx('xr6_ada_cplan'), 'Ada Cancelfirst', 'HT436 $72 discount Voucher', pg_temp.fx('xr6_ada_later'), pg_temp.fx('inv_ada'))
    and (pg_temp.tx('xr6_ada_cplan')::jsonb)->>'refund_due' = '72.00'
    and pg_temp.tx('xr6_ada_cplan') !~ 'came with VIP'
    and (pg_temp.tx('xr6_ada_res')::jsonb)->>'confirmation_required' = 'true'
    and pg_temp.later_ov((pg_temp.tx('xr6_ada_res')::jsonb->'revised_plan')::text) = pg_temp.later_ov(pg_temp.tx('xr6_ada_cplan'))
    and pg_temp.tx('xr6_ada_res2') = 'An Owner/Manager override reason is required for: vip_voucher_used_later'
    and (select status from approval_requests where id = (pg_temp.tx('xr6_ada_req')::jsonb->>'request_id')::uuid) = 'pending'
    and (select status::text || ' ' || paid_amount from invoices where id = pg_temp.fx('inv_ada')) = 'paid 72.00'
    and not exists (select 1 from invoice_refunds where invoice_id = pg_temp.fx('inv_ada'))
    and pg_temp.vstat(pg_temp.fx('inv_ada')) = '{"save72": "held", "three": "held"}'::jsonb,
  'XR6 Ada: Cancel asked for before SAVE72 was given on a later invoice: its approval (refund recorded) first shows the revised plan with the override, then is refused without a reason; nothing changes: ' || pg_temp.tx('xr6_ada_res2'));
select pg_temp.as_user('owner');
select pg_temp.putx('xr6_ben_later', pg_temp.save72_invoice(pg_temp.fx('ben'), 'line'));
select pg_temp.as_user('staff');
select pg_temp.put('xr6_ben_req', public.request_invoice_action_v2(pg_temp.fx('inv_ben'), 'cancel', '[]', 'Wrong day', null, gen_random_uuid())::text);
select pg_temp.as_user('owner');
select pg_temp.put('xr6_ben_res', public.resolve_invoice_action_v2((pg_temp.tx('xr6_ben_req')::jsonb->>'request_id')::uuid, true, 'Cancelled',
  pg_temp.tx('xr6_ben_req')::jsonb->'plan'->>'plan_hash',
  jsonb_build_array(jsonb_build_object('code', 'vip_voucher_used_later', 'reason', 'The SAVE72 on the mat was a separate offer')), null, true)::text);
select pg_temp.check((pg_temp.tx('xr6_ben_req')::jsonb)->>'status' = 'pending'
    and pg_temp.later_ov_is((pg_temp.tx('xr6_ben_req')::jsonb->'plan')::text, 'Ben Cancelafter', 'HT436 $72 discount Voucher',
                            pg_temp.fx('xr6_ben_later'), pg_temp.fx('inv_ben'))
    and (pg_temp.tx('xr6_ben_res')::jsonb)->>'status' = 'approved'
    and (select status::text || ' ' || paid_amount from invoices where id = pg_temp.fx('inv_ben')) = 'cancelled 0.00'
    and (select sum(amount) from invoice_refunds where invoice_id = pg_temp.fx('inv_ben')) = 72
    and pg_temp.vstat(pg_temp.fx('inv_ben')) = '{"save72": "revoked", "three": "revoked"}'::jsonb
    and (select count(*) from audit_logs a where a.record_id = pg_temp.fx('inv_ben') and a.action = 'vip_refund_used_later_allowed'
            and a.new_data @> jsonb_build_object('request_id', pg_temp.tx('xr6_ben_req')::jsonb->>'request_id',
                                                 'allowed_by', pg_temp.fx('owner'), 'later_invoice_no', pg_temp.ino(pg_temp.fx('xr6_ben_later')))) = 1,
  'XR6 Ben: SAVE72 given on a later invoice first: the Cancel request carries the override; the Owner approves it with a reason, its refund recorded: cancelled, S$72 back, both vouchers taken back, audited once: ' || left(pg_temp.tx('xr6_ben_res'), 120));
select pg_temp.as_user('owner');
select pg_temp.as_user('owner');
select pg_temp.putx('xr6_cat_later', pg_temp.save72_invoice(pg_temp.fx('cat'), 'invoice'));
select pg_temp.put('xr6_cat_cancel', pg_temp.err(format('select public.cancel_invoice_recorded(%L, %L, %L)', pg_temp.fx('inv_cat'), 'Wrong day', gen_random_uuid())));
-- "Record refund paid" on a cancelled invoice: money back with no line.
create function pg_temp.refund_due_paid(inv uuid, amount numeric) returns text language sql as
$$ select pg_temp.err(format('select public.refund_invoice_recorded(%L, %L, %L, %L, %L, %L)', inv,
     jsonb_build_array(jsonb_build_object('invoice_item_id', null, 'amount', amount)),
     jsonb_build_array(jsonb_build_object('payment_id', pg_temp.payment(inv), 'amount', amount)), '[]', 'Refund paid', gen_random_uuid())) $$;
select pg_temp.put('xr6_cat_all', pg_temp.refund_due_paid(pg_temp.fx('inv_cat'), 72));
select pg_temp.put('xr6_cat_part', pg_temp.refund_due_paid(pg_temp.fx('inv_cat'), 50));
select pg_temp.put('xr6_cat_rest', pg_temp.refund_due_paid(pg_temp.fx('inv_cat'), 22));
select pg_temp.check(pg_temp.tx('xr6_cat_cancel') = 'ok'
    and pg_temp.vstat(pg_temp.fx('inv_cat')) = '{"save72": "revoked", "three": "revoked"}'::jsonb
    and pg_temp.tx('xr6_cat_all') = pg_temp.later_cancelled_msg('Cat Directcancel', 'HT436 $72 discount Voucher', pg_temp.fx('xr6_cat_later'), pg_temp.fx('inv_cat'))
    and pg_temp.tx('xr6_cat_part') = 'ok'
    and pg_temp.tx('xr6_cat_rest') = pg_temp.tx('xr6_cat_all')
    and (select status::text || ' ' || paid_amount from invoices where id = pg_temp.fx('inv_cat')) = 'cancelled 22.00'
    and (select sum(amount) from invoice_refunds where invoice_id = pg_temp.fx('inv_cat')) = 50,
  'XR6 Cat: the Owner cancels straight away (the cancellation takes the vouchers back, as before); recording all S$72 of its refund due is refused, naming the later invoice; S$50 goes, the last S$22 is refused: ' || pg_temp.tx('xr6_cat_all'));
select pg_temp.as_user('staff');
select pg_temp.put('xr6_dan_req', public.request_invoice_action_v2(pg_temp.fx('inv_dan'), 'cancel', '[]', 'Wrong day', null, gen_random_uuid())::text);
select pg_temp.as_user('manager');
select pg_temp.put('xr6_dan_res', public.resolve_invoice_action_v2((pg_temp.tx('xr6_dan_req')::jsonb->>'request_id')::uuid, true, 'Cancelled',
  pg_temp.tx('xr6_dan_req')::jsonb->'plan'->>'plan_hash', '[]', null, true)::text);
select pg_temp.check(pg_temp.blockers((pg_temp.tx('xr6_dan_req')::jsonb->'plan')::text) = '[]'::jsonb
    and pg_temp.later_ov((pg_temp.tx('xr6_dan_req')::jsonb->'plan')::text) is null
    and (pg_temp.tx('xr6_dan_res')::jsonb)->>'status' = 'approved'
    and (select status::text from invoices where id = pg_temp.fx('inv_dan')) = 'cancelled'
    and (select sum(amount) from invoice_refunds where invoice_id = pg_temp.fx('inv_dan')) = 72
    and pg_temp.vstat(pg_temp.fx('inv_dan')) = '{"save72": "revoked", "three": "revoked"}'::jsonb,
  'XR6 Dan: nothing given later: Cancel with its refund recorded goes as before, the vouchers taken back: ' || left(pg_temp.tx('xr6_dan_res'), 200));

-- XR7 a counter VIP for two takes back each VIP's share. Ivy and Jo on two VIP lines with SAVE72 x2 and the 3-in-1 x2: Jo's
-- line refunded in full takes back one of each (one unit back to the van's stock each) and leaves Ivy's; Ivy's then takes
-- the rest. Kai and Lea on one line of two: S$72 back takes back one of each, Refund in full the other. Mo and Nat on one
-- line of two: S$71.99 back takes back nothing.
select pg_temp.as_user('owner');
insert into customers(full_name, phone) values
  ('Ivy Lineone', pg_temp.ph(174)), ('Jo Linetwo', pg_temp.ph(175)), ('Kai Qtytwo', pg_temp.ph(176)), ('Lea Qtypartner', pg_temp.ph(177)),
  ('Mo Nearlyall', pg_temp.ph(178)), ('Nat Nearlypartner', pg_temp.ph(179));
select pg_temp.putx(k, (select id from customers where full_name = n and deleted_at is null order by created_at desc limit 1))
  from (values ('ivy', 'Ivy Lineone'), ('jo', 'Jo Linetwo'), ('kai', 'Kai Qtytwo'), ('lea', 'Lea Qtypartner'), ('mo', 'Mo Nearlyall'),
               ('nat', 'Nat Nearlypartner')) x(k, n);
create function pg_temp.vip_ticket(qty int, people text[]) returns jsonb language sql as
$$ select jsonb_build_object('kind', 'event_ticket', 'event_ticket_option_id', pg_temp.fx('vip'), 'quantity', qty,
     'attendees', (select jsonb_agg(jsonb_build_object('name', c.full_name, 'customer_id', c.id) order by p.n)
                     from unnest(people) with ordinality p(k, n) join customers c on c.id = pg_temp.fx(p.k))) $$;
-- A counter VIP invoice for two: its ticket lines, SAVE72 x2 and the 3-in-1 x2 free, paid by bank transfer.
create function pg_temp.counter_vip_two(cust uuid, tickets jsonb) returns uuid language plpgsql as
$$declare v uuid; begin
  v := public.create_invoice_with_details(pg_temp.fx('van'), cust, tickets || jsonb_build_array(
    jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.fx('save72'), 'quantity', 2, 'is_foc', true, 'foc_reason', 'Included with VIP · counter'),
    jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.fx('three'), 'quantity', 2, 'is_foc', true, 'foc_reason', 'Included with VIP · counter')),
    jsonb_build_object('business_date', public.sg_today(), 'manual_discount', 0));
  perform public.record_invoice_payment(v, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('bank'),
    'amount', (select total_amount from invoices where id = v), 'reference', 'Counter VIP for two', 'payment_date', public.sg_today())), gen_random_uuid());
  return v;
end$$;
-- The VIP vouchers of an invoice: kind:status:quantity, and what each line took back (cancelled_unused_value).
create function pg_temp.vrows(inv uuid) returns text language sql as
$$ select string_agg(case v.voucher_id when pg_temp.fx('save72') then 'save72' when pg_temp.fx('three') then 'three' else '?' end
                     || ':' || v.status || ':' || v.quantity || ':' || b.cancelled_unused_value::int, ' '
                     order by v.voucher_id = pg_temp.fx('three'), v.status, v.id)
     from invoice_benefit_values b join customer_reward_vouchers v on v.id = b.reward_voucher_id where b.invoice_id = inv $$;
create function pg_temp.ticket_of(inv uuid, who text) returns uuid language sql as
$$ select it.id from invoice_items it join event_guests g on g.invoice_item_id = it.id
    where it.invoice_id = inv and it.line_kind = 'event_ticket' and g.customer_id = pg_temp.fx(who) limit 1 $$;
create function pg_temp.line_refund(inv uuid, item uuid, amount numeric) returns text language sql as
$$ select pg_temp.err(format('select public.refund_invoice_recorded(%L, %L, %L, %L, %L, %L)', inv,
     jsonb_build_array(jsonb_build_object('invoice_item_id', item, 'amount', amount)),
     jsonb_build_array(jsonb_build_object('payment_id', pg_temp.payment(inv), 'amount', amount)), '[]', 'One cannot come', gen_random_uuid())) $$;
-- (the two VIP vouchers limited for this, as in XF7, and unlimited again after)
update vouchers set qty_type = 'limited' where id in (pg_temp.fx('save72'), pg_temp.fx('three'));
insert into voucher_store_stock(voucher_id, store_id, current_qty) values (pg_temp.fx('save72'), pg_temp.fx('van'), 50), (pg_temp.fx('three'), pg_temp.fx('van'), 50)
  on conflict (voucher_id, store_id) do update set current_qty = 50;
select pg_temp.putx('inv_ivy', pg_temp.counter_vip_two(pg_temp.fx('ivy'), jsonb_build_array(pg_temp.vip_ticket(1, array['ivy']), pg_temp.vip_ticket(1, array['jo']))));
select pg_temp.putx('inv_kai', pg_temp.counter_vip_two(pg_temp.fx('kai'), jsonb_build_array(pg_temp.vip_ticket(2, array['kai', 'lea']))));
select pg_temp.putx('inv_mo', pg_temp.counter_vip_two(pg_temp.fx('mo'), jsonb_build_array(pg_temp.vip_ticket(2, array['mo', 'nat']))));
select pg_temp.put('xr7_s0', pg_temp.vstock());
select pg_temp.as_user('staff');
select pg_temp.put('xr7_jo_plan', public.invoice_action_plan(pg_temp.fx('inv_ivy'), 'refund_partial',
  jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.ticket_of(pg_temp.fx('inv_ivy'), 'jo'), 'quantity', 1)))::text);
select pg_temp.as_user('owner');
select pg_temp.put('xr7_jo', pg_temp.line_refund(pg_temp.fx('inv_ivy'), pg_temp.ticket_of(pg_temp.fx('inv_ivy'), 'jo'), 72));
select pg_temp.put('xr7_s1', pg_temp.vstock());
select pg_temp.check((select status::text || ' ' || total_amount from invoices where id = pg_temp.fx('inv_ivy')) = 'paid 144.00'
    and (pg_temp.tx('xr7_jo_plan')::jsonb)->'summary' @> jsonb_build_array(
        'Take back 1 of the 2 unused HT436 $72 discount Voucher that came with VIP from Ivy Lineone.',
        'Take back 1 of the 2 unused HT436 3-in-1 Vouchers that came with VIP from Ivy Lineone.')
    and (select jsonb_agg((b->>'units_revoked')::int) from jsonb_array_elements((pg_temp.tx('xr7_jo_plan')::jsonb)->'effects'->'benefits') b
          where b->>'line' like '%included with VIP') = '[1, 1]'::jsonb
    and pg_temp.tx('xr7_jo') = 'ok'
    and (select status::text from invoices where id = pg_temp.fx('inv_ivy')) = 'paid'
    and pg_temp.vrows(pg_temp.fx('inv_ivy')) = 'save72:held:1:1 three:held:1:1'
    and pg_temp.tx('xr7_s1') = (select string_agg((split_part(pg_temp.tx('xr7_s0'), '/', n)::int + 1)::text, '/' order by n) from generate_series(1, 2) n)
    and (select g.status::text from event_guests g where g.invoice_item_id = pg_temp.ticket_of(pg_temp.fx('inv_ivy'), 'ivy')) <> 'cancelled'
    and pg_temp.audits(pg_temp.fx('inv_ivy'), 'vip_voucher_taken_back') = 2
    and (select bool_and((a.new_data->>'units_taken_back')::int = 1 and a.new_data->>'status' = 'held') from audit_logs a
          where a.action = 'vip_voucher_taken_back' and a.record_id in (select b.reward_voucher_id from invoice_benefit_values b where b.invoice_id = pg_temp.fx('inv_ivy'))),
  'XR7 Ivy and Jo on two VIP lines: Jo''s line refunded says first and takes back 1 of the 2 of each (stock '
    || pg_temp.tx('xr7_s0') || ' to ' || pg_temp.tx('xr7_s1') || '); Ivy stays VIP with hers: ' || pg_temp.vrows(pg_temp.fx('inv_ivy')));
select pg_temp.as_user('staff');
select pg_temp.put('xr7_ivy_plan', public.invoice_action_plan(pg_temp.fx('inv_ivy'), 'refund_full', '[]')::text);
select pg_temp.as_user('owner');
select pg_temp.put('xr7_ivy', pg_temp.line_refund(pg_temp.fx('inv_ivy'), pg_temp.ticket_of(pg_temp.fx('inv_ivy'), 'ivy'), 72));
select pg_temp.check((pg_temp.tx('xr7_ivy_plan')::jsonb)->'summary' @> jsonb_build_array(
        'Take back the unused HT436 $72 discount Voucher that came with VIP from Ivy Lineone.',
        'Take back the unused HT436 3-in-1 Vouchers that came with VIP from Ivy Lineone.')
    and pg_temp.tx('xr7_ivy') = 'ok'
    and (select status::text from invoices where id = pg_temp.fx('inv_ivy')) = 'refunded'
    and pg_temp.vrows(pg_temp.fx('inv_ivy')) = 'save72:revoked:1:2 three:revoked:1:2'
    and pg_temp.vstock() = (select string_agg((split_part(pg_temp.tx('xr7_s0'), '/', n)::int + 2)::text, '/' order by n) from generate_series(1, 2) n),
  'XR7 then Ivy''s line: the rest is taken back (two of each in all, both back in stock): ' || pg_temp.vrows(pg_temp.fx('inv_ivy')));
select pg_temp.as_user('staff');
select pg_temp.put('xr7_kai_plan', public.invoice_action_plan(pg_temp.fx('inv_kai'), 'refund_partial',
  jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.ticket(pg_temp.fx('inv_kai')), 'quantity', 1)))::text);
select pg_temp.as_user('owner');
select pg_temp.put('xr7_kai', pg_temp.panel_refund(pg_temp.fx('inv_kai'), 72, 'Lea cannot come'));
select pg_temp.put('xr7_kai_rows', pg_temp.vrows(pg_temp.fx('inv_kai')));
select pg_temp.as_user('staff');
select pg_temp.put('xr7_kai_req', public.request_invoice_action_v2(pg_temp.fx('inv_kai'), 'refund_full', '[]', 'Kai cannot come either', null, gen_random_uuid())::text);
select pg_temp.as_user('manager');
select pg_temp.put('xr7_kai_res', public.resolve_invoice_action_v2((pg_temp.tx('xr7_kai_req')::jsonb->>'request_id')::uuid, true, 'Refunded',
  pg_temp.tx('xr7_kai_req')::jsonb->'plan'->>'plan_hash', '[]', null, false)::text);
select pg_temp.as_user('owner');
select pg_temp.put('xr7_mo', pg_temp.panel_refund(pg_temp.fx('inv_mo'), 71.99, 'Most of one'));
select pg_temp.check((pg_temp.tx('xr7_kai_plan')::jsonb)->'summary' @> jsonb_build_array(
        'Take back 1 of the 2 unused HT436 $72 discount Voucher that came with VIP from Kai Qtytwo.',
        'Take back 1 of the 2 unused HT436 3-in-1 Vouchers that came with VIP from Kai Qtytwo.')
    and pg_temp.tx('xr7_kai') = 'ok' and pg_temp.tx('xr7_kai_rows') = 'save72:held:1:1 three:held:1:1'
    and (pg_temp.tx('xr7_kai_req')::jsonb)->'plan'->'summary' @> jsonb_build_array(
        'Take back the unused HT436 $72 discount Voucher that came with VIP from Kai Qtytwo.')
    and (pg_temp.tx('xr7_kai_res')::jsonb)->>'status' = 'approved'
    and (select status::text from invoices where id = pg_temp.fx('inv_kai')) = 'refunded'
    and pg_temp.vrows(pg_temp.fx('inv_kai')) = 'save72:revoked:1:2 three:revoked:1:2'
    and pg_temp.tx('xr7_mo') = 'ok'
    and (select status::text from invoices where id = pg_temp.fx('inv_mo')) = 'paid'
    and pg_temp.vrows(pg_temp.fx('inv_mo')) = 'save72:held:2:0 three:held:2:0',
  'XR7 Kai and Lea on one line of two: S$72 back takes back 1 of the 2 of each (' || pg_temp.tx('xr7_kai_rows')
    || '), Refund in full the other; Mo and Nat: S$71.99 back takes back nothing (' || pg_temp.vrows(pg_temp.fx('inv_mo')) || ')');
update vouchers set qty_type = 'unlimited' where id in (pg_temp.fx('save72'), pg_temp.fx('three'));

-- XR8 a SAVE72 given while the VIP stood refunded does not count once its invoice is reopened and paid again (VIP again,
-- a new set); one given after that does.
select pg_temp.as_user('owner');
insert into customers(full_name, phone) values ('Oda Between', pg_temp.ph(180));
select pg_temp.putx('oda', (select id from customers where full_name = 'Oda Between' and deleted_at is null order by created_at desc limit 1));
select pg_temp.putx('inv_oda', pg_temp.counter_vip(pg_temp.fx('oda'), array[pg_temp.fx('save72'), pg_temp.fx('three')]));
select pg_temp.put('xr8_r1', pg_temp.panel_refund(pg_temp.fx('inv_oda'), 72, 'Refund in full'));
select pg_temp.putx('xr8_between', pg_temp.save72_invoice(pg_temp.fx('oda'), 'invoice'));
-- (one transaction is one moment: written as it happens, refunded in full a minute before the SAVE72 was given, while
-- it stood refunded, and reopened 30 seconds after it)
update audit_logs set created_at = now() - interval '1 minute' where record_id = pg_temp.fx('inv_oda') and action = 'vip_refund_vouchers';
select public.reopen_invoice(pg_temp.fx('inv_oda'), 'Refunded by mistake', gen_random_uuid());
update audit_logs set created_at = now() + interval '30 seconds' where record_id = pg_temp.fx('inv_oda') and action = 'invoice_reopened';
select public.record_invoice_payment(pg_temp.fx('inv_oda'), jsonb_build_array(jsonb_build_object(
  'payment_method_id', pg_temp.fx('bank'), 'amount', 72, 'reference', 'Paid again', 'payment_date', public.sg_today())), gen_random_uuid());
select pg_temp.as_user('staff');
select pg_temp.put('xr8_plan', public.invoice_action_plan(pg_temp.fx('inv_oda'), 'refund_full', '[]')::text);
-- (one transaction is one moment: every invoice made here is dated when this file began, before the reopening, so the
-- one made after it is written as it would be, a minute after the reopening)
select pg_temp.as_user('owner');
insert into invoices(invoice_no, store_id, customer_id, created_by, status, subtotal, discount_total, total_amount, paid_amount,
                     discount_voucher_id, business_date, created_at)
values ('HT436-A-' || pg_temp.tx('sfx'), pg_temp.fx('van'), pg_temp.fx('oda'), pg_temp.fx('owner'), 'unpaid', 100, 72, 28, 0,
        pg_temp.fx('save72'), public.sg_today(), (select reopened_at from invoices where id = pg_temp.fx('inv_oda')) + interval '1 minute');
select pg_temp.putx('xr8_after', (select id from invoices where invoice_no = 'HT436-A-' || pg_temp.tx('sfx')));
select pg_temp.as_user('staff');
select pg_temp.put('xr8_plan2', public.invoice_action_plan(pg_temp.fx('inv_oda'), 'refund_full', '[]')::text);
select pg_temp.check(pg_temp.tx('xr8_r1') = 'ok'
    and (pg_temp.tx('xr8_plan')::jsonb)->>'blocked' = 'false' and pg_temp.blockers(pg_temp.tx('xr8_plan')) = '[]'::jsonb
    and (pg_temp.tx('xr8_plan')::jsonb)->'summary' @> jsonb_build_array('Take back the unused HT436 $72 discount Voucher that came with VIP from Oda Between.')
    and pg_temp.later_ov(pg_temp.tx('xr8_plan')) is null
    and pg_temp.later_ov_is(pg_temp.tx('xr8_plan2'), 'Oda Between', 'HT436 $72 discount Voucher', pg_temp.fx('xr8_after'), pg_temp.fx('inv_oda')),
  'XR8 Oda: SAVE72 given while her VIP stood refunded (' || pg_temp.ino(pg_temp.fx('xr8_between')) || ') is not counted after it was reopened and paid again; one given after that is: '
    || coalesce(pg_temp.later_ov(pg_temp.tx('xr8_plan2'))::text, 'null'));

-- XR9 Pam: a VIP and a mat on one invoice (S$172), SAVE72 given on a later invoice. Refund in full and Cancel need the
-- override, a part refund of the mat alone does not, and the Finance panel's refund of the mat goes (of the VIP ticket, not). Quy: his VIP ticket refunded first (nothing given later then), SAVE72 given later: correcting his
-- payment (no money paid back) is not refused for that earlier refund.
select pg_temp.as_user('owner');
insert into customers(full_name, phone) values ('Pam Matalso', pg_temp.ph(181)), ('Quy Payfix', pg_temp.ph(182));
select pg_temp.putx(k, (select id from customers where full_name = n and deleted_at is null order by created_at desc limit 1))
  from (values ('pam', 'Pam Matalso'), ('quy', 'Quy Payfix')) x(k, n);
create function pg_temp.vip_and_mat(cust uuid) returns uuid language plpgsql as
$$declare v uuid; begin
  v := public.create_invoice_with_details(pg_temp.fx('van'), cust, jsonb_build_array(
      jsonb_build_object('kind', 'event_ticket', 'event_ticket_option_id', pg_temp.fx('vip'), 'quantity', 1,
        'attendees', jsonb_build_array(jsonb_build_object('name', (select full_name from customers where id = cust), 'customer_id', cust))),
      jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.fx('save72'), 'quantity', 1, 'is_foc', true, 'foc_reason', 'Included with VIP · counter'),
      jsonb_build_object('kind', 'voucher', 'voucher_id', pg_temp.fx('three'), 'quantity', 1, 'is_foc', true, 'foc_reason', 'Included with VIP · counter'),
      jsonb_build_object('kind', 'product', 'product_id', pg_temp.fx('mat'), 'quantity', 1)),
    jsonb_build_object('business_date', public.sg_today(), 'manual_discount', 0));
  perform public.record_invoice_payment(v, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('bank'),
    'amount', (select total_amount from invoices where id = v), 'reference', 'VIP and a mat', 'payment_date', public.sg_today())), gen_random_uuid());
  return v;
end$$;
create function pg_temp.mat_line(inv uuid) returns uuid language sql as
$$ select id from invoice_items where invoice_id = inv and line_kind = 'product' $$;
select pg_temp.putx('inv_pam', pg_temp.vip_and_mat(pg_temp.fx('pam')));
select pg_temp.putx('inv_quy', pg_temp.vip_and_mat(pg_temp.fx('quy')));
select pg_temp.putx('xr9_pam_later', pg_temp.save72_invoice(pg_temp.fx('pam'), 'invoice'));
select pg_temp.as_user('staff');
select pg_temp.put('xr9_full', public.invoice_action_plan(pg_temp.fx('inv_pam'), 'refund_full', '[]')::text);
select pg_temp.put('xr9_cancel', public.invoice_action_plan(pg_temp.fx('inv_pam'), 'cancel', '[]')::text);
select pg_temp.put('xr9_mat', public.invoice_action_plan(pg_temp.fx('inv_pam'), 'refund_partial',
  jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.mat_line(pg_temp.fx('inv_pam')), 'quantity', 1)))::text);
select pg_temp.put('xr9_mat_req', public.request_invoice_action_v2(pg_temp.fx('inv_pam'), 'refund_partial',
  jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.mat_line(pg_temp.fx('inv_pam')), 'quantity', 1)), 'The mat came back', null, gen_random_uuid())::text);
select pg_temp.as_user('owner');
select pg_temp.put('xr9_panel_ticket', pg_temp.panel_refund(pg_temp.fx('inv_pam'), 72, 'Refund the VIP'));
select pg_temp.put('xr9_panel_mat', pg_temp.err(format('select public.refund_invoice_recorded(%L, %L, %L, %L, %L, %L)', pg_temp.fx('inv_pam'),
  jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.mat_line(pg_temp.fx('inv_pam')), 'amount', 100)),
  jsonb_build_array(jsonb_build_object('payment_id', pg_temp.payment(pg_temp.fx('inv_pam')), 'amount', 100)),
  (select jsonb_agg(jsonb_build_object('movement_id', k->>'movement_id', 'sellable_quantity', 1, 'damaged_quantity', 0, 'not_returned_quantity', 0))
     from jsonb_array_elements((pg_temp.tx('xr9_mat')::jsonb)->'stock') k), 'The mat came back', gen_random_uuid())));
select pg_temp.check((select total_amount from invoices where id = pg_temp.fx('inv_pam')) = 172
    and pg_temp.later_ov_is(pg_temp.tx('xr9_full'), 'Pam Matalso', 'HT436 $72 discount Voucher', pg_temp.fx('xr9_pam_later'), pg_temp.fx('inv_pam'))
    and pg_temp.later_ov(pg_temp.tx('xr9_cancel')) = pg_temp.later_ov(pg_temp.tx('xr9_full'))
    and (pg_temp.tx('xr9_mat')::jsonb)->>'blocked' = 'false' and pg_temp.later_ov(pg_temp.tx('xr9_mat')) is null
    and pg_temp.tx('xr9_mat') !~ 'came with VIP'
    and (pg_temp.tx('xr9_mat_req')::jsonb)->>'status' = 'pending'
    and pg_temp.tx('xr9_panel_ticket') = pg_temp.later_err_msg('Pam Matalso', 'HT436 $72 discount Voucher', pg_temp.fx('xr9_pam_later'), pg_temp.fx('inv_pam'))
    and pg_temp.tx('xr9_panel_mat') = 'ok'
    and (select paid_amount from invoices where id = pg_temp.fx('inv_pam')) = 72
    and pg_temp.vstat(pg_temp.fx('inv_pam')) = '{"save72": "held", "three": "held"}'::jsonb,
  'XR9 Pam (VIP and a mat): Refund in full and Cancel need the override, a part refund of the mat does not (its request is raised); the Finance panel refunds the mat, not the VIP ticket: ' || pg_temp.tx('xr9_panel_ticket'));
select pg_temp.put('xr9_quy_r1', pg_temp.panel_refund(pg_temp.fx('inv_quy'), 72, 'VIP refunded'));
select pg_temp.putx('xr9_quy_later', pg_temp.save72_invoice(pg_temp.fx('quy'), 'invoice'));
select pg_temp.put('xr9_quy_fix', pg_temp.err(format('select public.correct_invoice_payment(%L, %L, %L, %L, %L, %L)',
  pg_temp.payment(pg_temp.fx('inv_quy')), 171, public.sg_today(), pg_temp.fx('bank'), 'Typo: S$171 arrived', gen_random_uuid())));
select pg_temp.check(pg_temp.tx('xr9_quy_r1') = 'ok'
    and pg_temp.vstat(pg_temp.fx('inv_quy')) = '{"save72": "revoked", "three": "revoked"}'::jsonb
    and pg_temp.tx('xr9_quy_fix') = 'ok'
    and (select status::text || ' ' || paid_amount from invoices where id = pg_temp.fx('inv_quy')) = 'partially_paid 99.00',
  'XR9 Quy: his VIP ticket refunded before SAVE72 was given later; his payment corrected afterwards (no money back) is not refused: ' || pg_temp.tx('xr9_quy_fix'));

-- ═════ XO The owner's answer, 21 Oct 2026: an Owner or Manager may allow the full refund ═════
-- A VIP voucher kind given as a discount on a later invoice still stops an automatic full refund, but no longer blocks the
-- guided Refund in full or Cancel: the plan carries the override vip_voucher_used_later (and the line "Owner/Manager
-- override required: ..."); staff may ask for it but never approve it, nor record a refund; an Owner or a Manager allows
-- it only with a reason, kept on the request's approval and in the audit log, with a row on the VIP invoice naming the
-- later invoice. A Cancel allowed that way, its money not recorded then, may be recorded as paid back afterwards. The
-- Finance panel still refuses a full refund (XR1, XR3).
select pg_temp.as_user('owner');
select pg_temp.put('xo_r', pg_temp.register('live', 'xo', jsonb_build_array(
  pg_temp.person(1, 'Opal', 'Ownerallows', pg_temp.ph(190), pg_temp.mail('xo-opal'), array[pg_temp.d(7)], true),
  pg_temp.person(2, 'Milo', 'Managerallows', pg_temp.ph(191), pg_temp.mail('xo-milo'), array[pg_temp.d(7)], true),
  pg_temp.person(3, 'Stan', 'Cancellater', pg_temp.ph(192), pg_temp.mail('xo-stan'), array[pg_temp.d(8)], true)))::text);
select pg_temp.putx(k, pg_temp.pid(pg_temp.tx('xo_r')::jsonb, n)) from (values ('opal', 1), ('milo', 2), ('stan', 3)) x(k, n);
select pg_temp.checkout('live', 'xo', array[pg_temp.tok(pg_temp.tx('xo_r')::jsonb, 1), pg_temp.tok(pg_temp.tx('xo_r')::jsonb, 2),
                                            pg_temp.tok(pg_temp.tx('xo_r')::jsonb, 3)]);
select pg_temp.put('xo_p', pg_temp.paid('live', 'xo', array[pg_temp.tok(pg_temp.tx('xo_r')::jsonb, 1), pg_temp.tok(pg_temp.tx('xo_r')::jsonb, 2),
                                                            pg_temp.tok(pg_temp.tx('xo_r')::jsonb, 3)], 21600)::text);
select pg_temp.putx('c_' || k, (pg_temp.pp(pg_temp.fx(k))).customer_id) from unnest(array['opal', 'milo', 'stan']) k;
select pg_temp.putx('inv_' || k, (select i.id from pg_temp.vinvoices('xo') i where i.customer_id = pg_temp.fx('c_' || k)))
  from unnest(array['opal', 'milo', 'stan']) k;
select pg_temp.putx('xo_later_' || k, pg_temp.save72_invoice(pg_temp.fx('c_' || k), 'invoice')) from unnest(array['opal', 'milo', 'stan']) k;
create function pg_temp.allowed_rows(inv uuid) returns bigint language sql as
$$ select count(*) from audit_logs a where a.record_id = inv and a.action = 'vip_refund_used_later_allowed' $$;
-- XO1 the Owner asks and allows it herself (the dialog's request, then its approval).
select pg_temp.put('xo1_plan', public.invoice_action_plan(pg_temp.fx('inv_opal'), 'refund_full', '[]')::text);
select pg_temp.put('xo1_req', public.request_invoice_action_v2(pg_temp.fx('inv_opal'), 'refund_full', '[]', 'Cannot come after all', null, gen_random_uuid())::text);
select pg_temp.put('xo1_none', pg_temp.err(format('select public.resolve_invoice_action_v2(%L, true, %L, %L, %L, null, false)',
  pg_temp.tx('xo1_req')::jsonb->>'request_id', 'Refunded', pg_temp.tx('xo1_req')::jsonb->'plan'->>'plan_hash', '[]')));
select pg_temp.put('xo1_after_none', (select status::text from invoices where id = pg_temp.fx('inv_opal')) || ' '
  || pg_temp.vcount(pg_temp.fx('inv_opal'), 'held') || ' ' || pg_temp.allowed_rows(pg_temp.fx('inv_opal')));
select pg_temp.put('xo1_res', public.resolve_invoice_action_v2((pg_temp.tx('xo1_req')::jsonb->>'request_id')::uuid, true, 'Refunded',
  pg_temp.tx('xo1_req')::jsonb->'plan'->>'plan_hash',
  jsonb_build_array(jsonb_build_object('code', 'vip_voucher_used_later', 'reason', 'Her SAVE72 on the mat was the shop''s own offer')),
  null, false)::text);
select pg_temp.check((pg_temp.tx('xo_p')::jsonb)->>'status' = 'invoiced'
    and pg_temp.later_ov_is(pg_temp.tx('xo1_plan'), 'Opal Ownerallows', 'HT436 $72 discount Voucher', pg_temp.fx('xo_later_opal'), pg_temp.fx('inv_opal'))
    and (pg_temp.tx('xo1_plan')::jsonb)->'summary' @> jsonb_build_array('Take back the unused HT436 $72 discount Voucher that came with VIP from Opal Ownerallows.')
    and pg_temp.tx('xo1_none') = 'An Owner/Manager override reason is required for: vip_voucher_used_later'
    and pg_temp.tx('xo1_after_none') = 'paid 2 0'
    and (pg_temp.tx('xo1_res')::jsonb)->>'status' = 'approved'
    and (select status::text from invoices where id = pg_temp.fx('inv_opal')) = 'refunded'
    and pg_temp.vcount(pg_temp.fx('inv_opal'), 'revoked') = 2 and pg_temp.vcount(pg_temp.fx('inv_opal'), 'held') = 0
    and public.event_web_person_vip_state(pg_temp.fx('opal')) = 'refunded'
    and (pg_temp.guest((pg_temp.pp(pg_temp.fx('opal'))).free_guest_id)).status = 'registered'
    and (select a.payload->'overrides' from approval_requests a where a.id = (pg_temp.tx('xo1_req')::jsonb->>'request_id')::uuid)
        @> jsonb_build_array(jsonb_build_object('code', 'vip_voucher_used_later', 'reason', 'Her SAVE72 on the mat was the shop''s own offer'))
    and exists (select 1 from audit_logs a where a.record_id = (pg_temp.tx('xo1_req')::jsonb->>'request_id')::uuid
                  and a.action = 'invoice_action_approved'
                  and a.new_data->'overrides' @> jsonb_build_array(jsonb_build_object('code', 'vip_voucher_used_later',
                                                                   'reason', 'Her SAVE72 on the mat was the shop''s own offer')))
    and pg_temp.allowed_rows(pg_temp.fx('inv_opal')) = 1
    and exists (select 1 from audit_logs a where a.record_id = pg_temp.fx('inv_opal') and a.action = 'vip_refund_used_later_allowed'
                  and a.module = 'events'
                  and a.new_data @> jsonb_build_object('request_id', pg_temp.tx('xo1_req')::jsonb->>'request_id', 'allowed_by', pg_temp.fx('owner'),
                                                       'later_invoice_no', pg_temp.ino(pg_temp.fx('xo_later_opal')),
                                                       'voucher', 'HT436 $72 discount Voucher', 'holder', 'Opal Ownerallows')
                  and a.reason = 'VIP refunded in full on an Owner''s or Manager''s override: a discount with the HT436 $72 discount Voucher was given on '
                                 || pg_temp.ino(pg_temp.fx('xo_later_opal')) || ' (the reason is on the approved request)'),
  'XO1 the Owner allows a full refund though SAVE72 was given on a later invoice: the plan shows the override; refused without a reason (nothing changes), refunded in full with one (both vouchers taken back, VIP ended, the free record back); the reason kept on the approval and in the audit log; one row on the invoice names the later invoice: ' || left(pg_temp.tx('xo1_res'), 100));
-- XO2 staff ask; staff cannot allow it, nor record the refund themselves; a Manager allows it.
select pg_temp.as_user('staff');
select pg_temp.put('xo2_req', public.request_invoice_action_v2(pg_temp.fx('inv_milo'), 'refund_full', '[]', 'Cannot come', null, gen_random_uuid())::text);
select pg_temp.put('xo2_staff', pg_temp.err(format('select public.resolve_invoice_action_v2(%L, true, %L, %L, %L, null, false)',
  pg_temp.tx('xo2_req')::jsonb->>'request_id', 'Refunded', pg_temp.tx('xo2_req')::jsonb->'plan'->>'plan_hash',
  jsonb_build_array(jsonb_build_object('code', 'vip_voucher_used_later', 'reason', 'Staff allow it')))));
select pg_temp.put('xo2_staff_panel', pg_temp.panel_refund(pg_temp.fx('inv_milo'), 72, 'Staff refund in full'));
select pg_temp.put('xo2_mid', (select status::text from invoices where id = pg_temp.fx('inv_milo')) || ' '
  || pg_temp.vcount(pg_temp.fx('inv_milo'), 'held') || ' ' || pg_temp.allowed_rows(pg_temp.fx('inv_milo')));
select pg_temp.as_user('manager');
select pg_temp.put('xo2_res', public.resolve_invoice_action_v2((pg_temp.tx('xo2_req')::jsonb->>'request_id')::uuid, true, 'Refunded',
  pg_temp.tx('xo2_req')::jsonb->'plan'->>'plan_hash',
  jsonb_build_array(jsonb_build_object('code', 'vip_voucher_used_later', 'reason', 'Agreed with the Owner by phone')), null, false)::text);
select pg_temp.check((pg_temp.tx('xo2_req')::jsonb)->>'status' = 'pending'
    and pg_temp.later_ov_is((pg_temp.tx('xo2_req')::jsonb->'plan')::text, 'Milo Managerallows', 'HT436 $72 discount Voucher',
                            pg_temp.fx('xo_later_milo'), pg_temp.fx('inv_milo'))
    and pg_temp.tx('xo2_staff') = 'Only an Owner or Manager can approve or reject an invoice request'
    and pg_temp.tx('xo2_staff_panel') = 'Only an Owner or Manager can record a refund'
    and pg_temp.tx('xo2_mid') = 'paid 2 0'
    and (pg_temp.tx('xo2_res')::jsonb)->>'status' = 'approved'
    and (select status::text from invoices where id = pg_temp.fx('inv_milo')) = 'refunded'
    and pg_temp.vcount(pg_temp.fx('inv_milo'), 'revoked') = 2
    and pg_temp.allowed_rows(pg_temp.fx('inv_milo')) = 1
    and exists (select 1 from audit_logs a where a.record_id = pg_temp.fx('inv_milo') and a.action = 'vip_refund_used_later_allowed'
                  and a.new_data @> jsonb_build_object('request_id', pg_temp.tx('xo2_req')::jsonb->>'request_id', 'allowed_by', pg_temp.fx('manager'))),
  'XO2 staff ask for the refund in full (the plan carries the override) but cannot approve it or record it; a Manager allows it with a reason: refunded, both vouchers taken back, audited: ' || pg_temp.tx('xo2_staff'));
-- XO3 a Cancel allowed with a reason by a Manager, its S$72 not recorded then; recorded as paid back later in the Finance panel.
select pg_temp.as_user('staff');
select pg_temp.put('xo3_req', public.request_invoice_action_v2(pg_temp.fx('inv_stan'), 'cancel', '[]', 'Wrong day', null, gen_random_uuid())::text);
select pg_temp.as_user('manager');
select pg_temp.put('xo3_res', public.resolve_invoice_action_v2((pg_temp.tx('xo3_req')::jsonb->>'request_id')::uuid, true, 'Cancelled',
  pg_temp.tx('xo3_req')::jsonb->'plan'->>'plan_hash',
  jsonb_build_array(jsonb_build_object('code', 'vip_voucher_used_later', 'reason', 'The later SAVE72 was a separate offer')), null, false)::text);
select pg_temp.put('xo3_mid', (select status::text || ' ' || paid_amount from invoices where id = pg_temp.fx('inv_stan')));
select pg_temp.as_user('owner');
select pg_temp.put('xo3_paid', pg_temp.refund_due_paid(pg_temp.fx('inv_stan'), 72));
select pg_temp.check(pg_temp.later_ov_is((pg_temp.tx('xo3_req')::jsonb->'plan')::text, 'Stan Cancellater', 'HT436 $72 discount Voucher',
                                         pg_temp.fx('xo_later_stan'), pg_temp.fx('inv_stan'))
    and (pg_temp.tx('xo3_res')::jsonb)->>'status' = 'approved' and pg_temp.tx('xo3_mid') = 'cancelled 72.00'
    and pg_temp.tx('xo3_paid') = 'ok'
    and (select status::text || ' ' || paid_amount from invoices where id = pg_temp.fx('inv_stan')) = 'cancelled 0.00'
    and (select sum(amount) from invoice_refunds where invoice_id = pg_temp.fx('inv_stan')) = 72
    and pg_temp.vstat(pg_temp.fx('inv_stan')) = '{"save72": "revoked", "three": "revoked"}'::jsonb
    and pg_temp.allowed_rows(pg_temp.fx('inv_stan')) = 1
    and exists (select 1 from audit_logs a where a.record_id = pg_temp.fx('inv_stan') and a.action = 'vip_refund_used_later_allowed'
                  and a.new_data @> jsonb_build_object('request_id', pg_temp.tx('xo3_req')::jsonb->>'request_id', 'allowed_by', pg_temp.fx('manager'),
                                                       'reason', 'The later SAVE72 was a separate offer')),
  'XO3 a Cancel allowed by a Manager with a reason (its money not recorded then): the S$72 recorded as paid back later in the Finance panel goes, audited with the Manager''s reason: ' || pg_temp.tx('xo3_paid'));
-- XO4 (the review of 21 Oct 2026) the reason an Owner or Manager gave is added to the VIP invoice's audit log as 417
-- stores the approval (vip_refund_used_later_reason): Opal's and Milo's refunds in full, once each; Stan's Cancel, whose
-- money was recorded later, has the reason on the row written then, so no second row.
create function pg_temp.reason_rows(inv uuid) returns bigint language sql as
$$ select count(*) from audit_logs a where a.record_id = inv and a.action = 'vip_refund_used_later_reason' $$;
select pg_temp.check(pg_temp.reason_rows(pg_temp.fx('inv_opal')) = 1 and pg_temp.reason_rows(pg_temp.fx('inv_milo')) = 1
    and pg_temp.reason_rows(pg_temp.fx('inv_stan')) = 0
    and exists (select 1 from audit_logs a where a.record_id = pg_temp.fx('inv_opal') and a.action = 'vip_refund_used_later_reason'
                  and a.table_name = 'invoices' and a.module = 'events'
                  and a.new_data @> jsonb_build_object('request_id', pg_temp.tx('xo1_req')::jsonb->>'request_id', 'allowed_by', pg_temp.fx('owner'),
                                                       'reason', 'Her SAVE72 on the mat was the shop''s own offer')
                  and a.reason = 'The reason given for refunding the VIP in full on an Owner''s or Manager''s override: '
                                 || 'Her SAVE72 on the mat was the shop''s own offer')
    and exists (select 1 from audit_logs a where a.record_id = pg_temp.fx('inv_milo') and a.action = 'vip_refund_used_later_reason'
                  and a.new_data @> jsonb_build_object('request_id', pg_temp.tx('xo2_req')::jsonb->>'request_id', 'allowed_by', pg_temp.fx('manager'),
                                                       'reason', 'Agreed with the Owner by phone')),
  'XO4 the reason the Owner or Manager gave is added to the VIP invoice''s audit log as the approval is stored (once; not again for a Cancel whose money was recorded later, whose row quotes it)');
-- XO5 (the review of 21 Oct 2026) a Cancel approved while nothing was given later (no override); SAVE72 given after the
-- cancellation, which took the VIP vouchers back, is not theirs: the S$72 refund due is recorded in full as usual. (One
-- transaction here, so the later invoice is dated a minute after the cancellation; event-website-separate-tx.sql runs
-- it as it happens.)
select pg_temp.as_user('owner');
select pg_temp.put('xo5_r', pg_temp.register('live', 'xo5', jsonb_build_array(
  pg_temp.person(1, 'Vic', 'Cancelfirst', pg_temp.ph(275), pg_temp.mail('xo5-vic'), array[pg_temp.d(7)], true)))::text);
select pg_temp.checkout('live', 'xo5', array[pg_temp.tok(pg_temp.tx('xo5_r')::jsonb, 1)]);
select pg_temp.put('xo5_p', pg_temp.paid('live', 'xo5', array[pg_temp.tok(pg_temp.tx('xo5_r')::jsonb, 1)], 7200)::text);
select pg_temp.putx('inv_vic', (select i.id from pg_temp.vinvoices('xo5') i));
select pg_temp.putx('c_vic', (select i.customer_id from invoices i where i.id = pg_temp.fx('inv_vic')));
select pg_temp.as_user('staff');
select pg_temp.put('xo5_req', public.request_invoice_action_v2(pg_temp.fx('inv_vic'), 'cancel', '[]', 'Wrong day', null, gen_random_uuid())::text);
select pg_temp.as_user('manager');
select pg_temp.put('xo5_res', public.resolve_invoice_action_v2((pg_temp.tx('xo5_req')::jsonb->>'request_id')::uuid, true, 'Cancelled',
  pg_temp.tx('xo5_req')::jsonb->'plan'->>'plan_hash', '[]', null, false)::text);
select pg_temp.as_user('owner'), set_config('invoice.therapy_reviewed', '', true);
select pg_temp.putx('xo5_later', pg_temp.save72_invoice(pg_temp.fx('c_vic'), 'invoice'));
alter table invoices disable trigger invoice_created_at_immutable;
update invoices set created_at = now() + interval '1 minute' where id = pg_temp.fx('xo5_later');
alter table invoices enable trigger invoice_created_at_immutable;
select pg_temp.put('xo5_seen', coalesce(public.event_vip_used_later(pg_temp.fx('inv_vic'))::text, 'none'));
select pg_temp.put('xo5_paid', pg_temp.refund_due_paid(pg_temp.fx('inv_vic'), 72));
select pg_temp.check((pg_temp.tx('xo5_p')::jsonb)->>'status' = 'invoiced'
    and pg_temp.later_ov((pg_temp.tx('xo5_req')::jsonb->'plan')::text) is null
    and (pg_temp.tx('xo5_res')::jsonb)->>'status' = 'approved'
    and pg_temp.tx('xo5_seen') = 'none' and pg_temp.tx('xo5_paid') = 'ok'
    and (select status::text || ' ' || paid_amount from invoices where id = pg_temp.fx('inv_vic')) = 'cancelled 0.00'
    and pg_temp.vstat(pg_temp.fx('inv_vic')) = '{"save72": "revoked", "three": "revoked"}'::jsonb
    and pg_temp.allowed_rows(pg_temp.fx('inv_vic')) = 0,
  'XO5 a Cancel approved before any later discount; SAVE72 given after the cancellation (which took the VIP vouchers back) is not counted: the S$72 refund due is recorded in full, no override needed: ' || pg_temp.tx('xo5_paid'));

-- ═════ FS No self-referral (the owner, 20 Oct 2026, 18:0x; narrowed ~20:15) ═════
-- A person through an affiliate's link who is that affiliate (her own record,
-- or her name in the same words) is not referred and earns nothing; the
-- registration goes through and staff see a plain note. Her phone or email
-- inbox alone no longer makes someone her (the owner, ~20:15, A): such a
-- person is held, and made a customer by staff they wait for an Owner's or
-- Manager's check (section FA).
select pg_temp.as_user('owner');
do $$ declare c uuid; begin
  -- A second affiliate, with a Gmail address (for the inbox match).
  insert into customers(full_name, phone, email)
  values ('Gail Selfmail', pg_temp.ph(210), 'gail.self.ht' || lower(pg_temp.tx('sfx')) || '@gmail.com') returning id into c;
  insert into customer_affiliates(customer_id, status, referral_code) values (c, 'active', 'HG' || pg_temp.tx('sfx'));
  insert into fx values ('gail', c);
  insert into tx values ('code_gail', 'HG' || pg_temp.tx('sfx'));
end $$;
create function pg_temp.fs(tag text, pos int) returns public.event_registration_people language sql as
$$ select pg_temp.pp(pg_temp.pid(pg_temp.tx(tag)::jsonb, pos)) $$;
-- Her own row says "She earns no commission from it" (the owner, 21 Oct 2026; her own referrer still earns on her VIP);
-- recognised by her name (or her name and her phone or inbox) but not linked to her record yet: what staff may do.
create function pg_temp.self_note(how text, aff text, code text) returns text language sql as
$$ select case when how = 'customer' then format('Not referred: this is %s, the affiliate whose link (%s) was used. She earns no commission from it.', aff, code)
               else format('Not referred: the same %s as %s, the affiliate whose link (%s) was used. If this is %s, link her record: '
                           || 'she earns no commission from it. If it is someone else, make a new customer: they are not referred '
                           || 'through this link either.', how, aff, code, aff) end $$;
-- Someone else with her name, made a new customer by staff from To match (the owner, 21 Oct 2026).
create function pg_temp.self_other_note(how text, aff text, code text) returns text language sql as
$$ select format('Not referred: the same %s as %s, the affiliate whose link (%s) was used, but staff made them a separate '
                 || 'customer (someone else), so no referral or commission comes from this link.', how, aff, code) $$;
-- Someone on another customer's phone through the link (Q19; the owner, 21 Oct 2026): held, then waiting for the check.
create function pg_temp.other_phone_note(aff text, code text) returns text language sql as
$$ select format('Their phone is on another customer''s record. If this is that customer, link their record: an existing customer '
                 || 'is not referred through this link (%s). If it is someone else, make a new customer: they become %s''s referral '
                 || 'once an Owner or Manager checks them as a different person (Affiliates page), and no commission comes before that.', code, aff) $$;
create function pg_temp.other_waiting_note(aff text, code text) returns text language sql as
$$ select format('Waiting for a check: their phone is on another customer''s record. They become %s''s referral (link %s) '
                 || 'once an Owner or Manager checks them as a different person (Affiliates page); no commission comes before that.', aff, code) $$;
-- Someone else on the affiliate's phone or email inbox, held for staff (the owner, ~20:15, A).
create function pg_temp.shares_note(how text, aff text, code text) returns text language sql as
$$ select format('Shares the %s of %s, the affiliate whose link (%s) was used. If this is %s, link that record: not referred. '
                 || 'If it is someone else, make a new customer: they become %s''s referral once an Owner or Manager checks them '
                 || 'as a different person (Affiliates page), and no commission comes before that.', how, aff, code, aff, aff) $$;
create function pg_temp.waiting_note(how text, aff text, code text) returns text language sql as
$$ select format('Waiting for a check: shares the %s of %s, the affiliate whose link (%s) was used. They become %s''s referral '
                 || 'once an Owner or Manager checks them as a different person (Affiliates page); no commission comes before that.',
                 how, aff, code, aff) $$;
-- An existing customer through the link (the owner, ~20:15, D).
create function pg_temp.existing_note(code text, referrer text) returns text language sql as
$$ select case when referrer is null
               then format('Already a customer, so not referred again through this link (%s); they had no referral before, and none is added.', code)
               when referrer = '?'
               then format('Already a customer, so not referred again through this link (%s); any referral they already have still stands.', code)
               else format('Already a customer, so not referred again through this link (%s); their existing referral (by %s) still stands.', code, referrer) end $$;
create function pg_temp.self_audits(pid uuid) returns bigint language sql as
$$ select count(*) from audit_logs a where a.table_name = 'event_registration_people' and a.record_id = pid
      and a.action = 'event_registration_self_referral' $$;
-- FS1 the affiliate through her own link on a phone and email not on file, her name in other words (the owner, 21 Oct
-- 2026): registered and on the guest list, but held for staff under To match with her record to link; nobody's referral.
select pg_temp.put('fs1', pg_temp.register('live', 'fs1', jsonb_build_array(
  pg_temp.person(1, 'Testlink', 'Aff', pg_temp.ph(200), pg_temp.mail('fs1'), array[pg_temp.d(7)])), pg_temp.tx('code_ok'))::text);
select pg_temp.check((pg_temp.tx('fs1')::jsonb)->>'status' = 'registered' and not pg_temp.says_who(pg_temp.tx('fs1')::jsonb)
    and (select array_agg(k order by k) from jsonb_object_keys(pg_temp.tx('fs1')::jsonb) k) = array['ok', 'people', 'registration_id', 'status', 'test']
    and (select array_agg(k order by k) from jsonb_object_keys((pg_temp.tx('fs1')::jsonb)->'people'->0) k)
        = array['already_registered', 'days', 'person_id', 'position', 'upgrade_token', 'vip']
    and (pg_temp.fs('fs1', 1)).match = 'held' and (pg_temp.fs('fs1', 1)).hold_reason = 'affiliate_name'
    and (pg_temp.fs('fs1', 1)).candidate_customer_ids = array[pg_temp.fx('aff')]
    and (pg_temp.fs('fs1', 1)).customer_id is null
    and (pg_temp.fs('fs1', 1)).referral_outcome = 'self'
    and (pg_temp.fs('fs1', 1)).referral_self_by = array['name']
    and not exists (select 1 from customers c where public.normalize_customer_phone(c.phone) = pg_temp.ph(200))
    and not exists (select 1 from referral_signup_events e where e.normalized_phone = pg_temp.ph(200))
    and (pg_temp.guest((pg_temp.fs('fs1', 1)).free_guest_id)).status = 'registered'
    and (pg_temp.guest((pg_temp.fs('fs1', 1)).free_guest_id)).customer_id is null,
  'FS1 the affiliate through her own link on a phone and email not on file (her name in other words): registered and on the guest list, held for staff with her own record to link (the owner, 21 Oct 2026); no customer made, nobody''s referral');
select pg_temp.check(pg_temp.self_audits((pg_temp.fs('fs1', 1)).id) = 1
    and exists (select 1 from audit_logs a where a.record_id = (pg_temp.fs('fs1', 1)).id and a.action = 'event_registration_self_referral'
                  and a.module = 'affiliate' and a.reason = pg_temp.self_note('name', 'Aff Testlink', pg_temp.tx('code_ok'))
                  and a.new_data @> jsonb_build_object('referral_code', pg_temp.tx('code_ok'), 'referrer_customer_id', pg_temp.fx('aff'),
                                                       'self_by', jsonb_build_array('name'), 'registration_id', pg_temp.bid('REG', 'fs1'))),
  'FS1 one audit row (filed under affiliate) with the plain note: ' || pg_temp.self_note('name', 'Aff Testlink', pg_temp.tx('code_ok')));
-- FS2 the affiliate on her own record (F3): self, by everything, no duplicate event, her own referrer untouched.
select pg_temp.check((pg_temp.f1(3)).referral_outcome = 'self'
    and (pg_temp.f1(3)).referral_self_by = array['customer', 'name', 'phone', 'email']
    and not exists (select 1 from referral_signup_events e where e.normalized_phone = pg_temp.ph(900))
    and (select referred_by from customers where id = pg_temp.fx('aff')) = pg_temp.fx('upline')
    and pg_temp.self_audits((pg_temp.f1(3)).id) = 1
    and public.event_web_referral_note((pg_temp.f1(3)).id) = pg_temp.self_note('customer', 'Aff Testlink', pg_temp.tx('code_ok')),
  'FS2 the affiliate on her own record through her link: self (her record, name, phone and email), no duplicate event, her own referrer kept');
-- FS3 one form through the link: the affiliate (her name, a new phone), two real referrals (one with a name
-- like hers but not hers), a family member on another customer's phone (Q19), and one on the affiliate's phone.
select pg_temp.put('fs3', pg_temp.register('live', 'fs3', jsonb_build_array(
  pg_temp.person(1, 'Aff', 'Testlink', pg_temp.ph(201), pg_temp.mail('fs3-1'), array[pg_temp.d(7)]),
  pg_temp.person(2, 'Rina', 'Realref', pg_temp.ph(202), pg_temp.mail('fs3-2'), array[pg_temp.d(7)]),
  pg_temp.person(3, 'Aff', 'Testlinx', pg_temp.ph(203), pg_temp.mail('fs3-3'), array[pg_temp.d(8)]),
  pg_temp.person(4, 'Hugo', 'Sharedphone', pg_temp.ph(3), pg_temp.mail('fs3-4'), array[pg_temp.d(7)]),
  pg_temp.person(5, 'Fay', 'Familyofaff', pg_temp.ph(900), pg_temp.mail('fs3-5'), array[pg_temp.d(8)])), pg_temp.tx('code_ok'))::text);
select pg_temp.putx('rina', (pg_temp.fs('fs3', 2)).customer_id);
select pg_temp.putx('testlinx', (pg_temp.fs('fs3', 3)).customer_id);
select pg_temp.check((pg_temp.fs('fs3', 1)).referral_outcome = 'self' and (pg_temp.fs('fs3', 1)).referral_self_by = array['name']
    and (pg_temp.fs('fs3', 1)).match = 'held' and (pg_temp.fs('fs3', 1)).hold_reason = 'affiliate_name'
    and (pg_temp.fs('fs3', 1)).customer_id is null and (pg_temp.fs('fs3', 1)).candidate_customer_ids = array[pg_temp.fx('aff')]
    and (pg_temp.fs('fs3', 2)).referral_outcome = 'created' and (pg_temp.fs('fs3', 2)).referral_self_by is null
    and (select (referred_by, referral_source) = (pg_temp.fx('aff'), 'affiliate_link') from customers where id = pg_temp.fx('rina'))
    and exists (select 1 from referral_signup_events e where e.new_customer_id = pg_temp.fx('rina') and e.outcome = 'created')
    and pg_temp.self_audits((pg_temp.fs('fs3', 2)).id) = 0,
  'FS3 one form: the affiliate on it (her name, a new phone and email: held with her record to link) is not referred; the real referral on the same form is');
select pg_temp.check((pg_temp.fs('fs3', 3)).referral_outcome = 'created' and (pg_temp.fs('fs3', 3)).referral_self_by is null
    and (select referred_by from customers where id = pg_temp.fx('testlinx')) = pg_temp.fx('aff')
    and pg_temp.self_audits((pg_temp.fs('fs3', 3)).id) = 0,
  'FS3 someone whose name is like the affiliate''s but not hers ("Aff Testlinx") is still her referral');
select pg_temp.check((pg_temp.fs('fs3', 4)).match = 'held' and (pg_temp.fs('fs3', 4)).hold_reason = 'phone_in_use'
    and (pg_temp.fs('fs3', 4)).referral_outcome = 'held' and (pg_temp.fs('fs3', 4)).referral_self_by is null
    and (pg_temp.fs('fs3', 5)).match = 'held' and (pg_temp.fs('fs3', 5)).hold_reason = 'phone_in_use'
    and (pg_temp.fs('fs3', 5)).referral_outcome = 'held' and (pg_temp.fs('fs3', 5)).referral_self_by is null
    and (pg_temp.fs('fs3', 5)).candidate_customer_ids = array[pg_temp.fx('aff')]
    and pg_temp.self_audits((pg_temp.fs('fs3', 5)).id) = 0,
  'FS3 held for staff, both waiting for staff (referral held): the family member on another customer''s phone, and the one on the affiliate''s own phone under another name (no longer "self", the owner ~20:15)');
-- FS4 through Gail's link, a different name and phone, her Gmail inbox written another way: held for staff (the email), not referred.
select pg_temp.put('fs4', pg_temp.register('live', 'fs4', jsonb_build_array(
  pg_temp.person(1, 'Gee', 'Otherway', pg_temp.ph(211), 'GailSelfHT' || pg_temp.tx('sfx') || '+seminar@googlemail.com', array[pg_temp.d(7)])),
  pg_temp.tx('code_gail'))::text);
select pg_temp.check((pg_temp.fs('fs4', 1)).match = 'held' and (pg_temp.fs('fs4', 1)).hold_reason = 'email_in_use'
    and (pg_temp.fs('fs4', 1)).referral_outcome = 'held' and (pg_temp.fs('fs4', 1)).referral_self_by is null
    and public.event_web_affiliate_contact((pg_temp.fs('fs4', 1)).id) = array['email']
    and pg_temp.self_audits((pg_temp.fs('fs4', 1)).id) = 0,
  'FS4 the affiliate''s email inbox (Gmail, dots, +tag, googlemail) under another name through her link: held for staff, the referral waits (not "self")');
-- What staff see: the note on the guest, on To match, and none on a real referral.
select pg_temp.as_user('staff');
select pg_temp.put('fs_x', public.event_web_guest_extras(pg_temp.fx('ev'))::text);
create function pg_temp.fs_extra(gid uuid) returns jsonb language sql as
$$ select g from jsonb_array_elements(pg_temp.tx('fs_x')::jsonb->'guests') g where (g->>'guest_id')::uuid = gid $$;
create function pg_temp.fs_hold(pid uuid) returns jsonb language sql as
$$ select h from jsonb_array_elements(pg_temp.tx('fs_x')::jsonb->'holds') h where (h->>'person_id')::uuid = pid $$;
select pg_temp.check(pg_temp.fs_extra((pg_temp.fs('fs1', 1)).free_guest_id)->'referral'
        @> jsonb_build_object('code', pg_temp.tx('code_ok'), 'outcome', 'self', 'note', pg_temp.self_note('name', 'Aff Testlink', pg_temp.tx('code_ok')))
    and pg_temp.fs_extra((pg_temp.fs('fs3', 2)).free_guest_id)->'referral' @> '{"outcome": "created", "note": null}'::jsonb
    and pg_temp.fs_hold((pg_temp.fs('fs3', 5)).id)->>'referral_note' = pg_temp.shares_note('phone', 'Aff Testlink', pg_temp.tx('code_ok'))
    and pg_temp.fs_hold((pg_temp.fs('fs4', 1)).id)->>'referral_note' = pg_temp.shares_note('email inbox', 'Gail Selfmail', pg_temp.tx('code_gail'))
    and pg_temp.fs_hold((pg_temp.fs('fs3', 4)).id)->>'referral_note' = pg_temp.other_phone_note('Aff Testlink', pg_temp.tx('code_ok'))
    and pg_temp.fs_hold((pg_temp.fs('fs1', 1)).id)->>'referral_note' = pg_temp.self_note('name', 'Aff Testlink', pg_temp.tx('code_ok'))
    and pg_temp.fs_hold((pg_temp.fs('fs1', 1)).id)->>'reason' = 'affiliate_name'
    and exists (select 1 from jsonb_array_elements(pg_temp.fs_hold((pg_temp.fs('fs1', 1)).id)->'candidates') c
                 where (c->>'customer_id')::uuid = pg_temp.fx('aff') and (c->>'name_matches')::boolean
                   and not (c->>'phone_matches')::boolean and not (c->>'email_matches')::boolean),
  'FS5 staff see the plain note on the guest (Guests tab) and on To match (under her name: link her record or make someone else a customer, her record the candidate; on the affiliate''s phone or email, or another customer''s phone: what linking or making a customer does); none on a real referral');
-- Staff match the held ones.
select pg_temp.put('fs6_hugo', pg_temp.err(format('select public.event_registration_create_customer(%L, %L)', (pg_temp.fs('fs3', 4)).id, 'Brother of Rosa, same phone')));
select pg_temp.put('fs6_fay', pg_temp.err(format('select public.event_registration_create_customer(%L, %L)', (pg_temp.fs('fs3', 5)).id, 'Daughter of the affiliate, same phone')));
select pg_temp.put('fs6_gee', pg_temp.err(format('select public.event_registration_attach(%L, %L, %L)', (pg_temp.fs('fs4', 1)).id, pg_temp.fx('gail'), 'Gail herself, a nickname')));
select pg_temp.putx('hugo', (pg_temp.fs('fs3', 4)).customer_id);
select pg_temp.putx('fay', (pg_temp.fs('fs3', 5)).customer_id);
select pg_temp.check(pg_temp.tx('fs6_hugo') = 'ok' and (pg_temp.fs('fs3', 4)).referral_outcome = 'check_waiting'
    and (select referred_by from customers where id = pg_temp.fx('hugo')) is null
    and exists (select 1 from referral_signup_checks k where k.customer_id = pg_temp.fx('hugo') and k.status = 'pending'
                  and k.referrer_customer_id = pg_temp.fx('aff')
                  and pg_temp.fx('c_phone') = any (k.phone_shared_with) and not pg_temp.fx('aff') = any (k.phone_shared_with))
    and exists (select 1 from referral_signup_events e where e.new_customer_id = pg_temp.fx('hugo') and e.outcome = 'phone_shared')
    and public.event_web_referral_note((pg_temp.fs('fs3', 4)).id) = pg_temp.other_waiting_note('Aff Testlink', pg_temp.tx('code_ok')),
  'FS6 Q19 = A (the owner, 21 Oct 2026): staff make a customer of the one on another customer''s phone: no referrer yet, a pending check, the note says it waits: ' || pg_temp.tx('fs6_hugo'));
select pg_temp.check(pg_temp.tx('fs6_fay') = 'ok' and (pg_temp.fs('fs3', 5)).match = 'staff_created'
    and (pg_temp.fs('fs3', 5)).referral_outcome = 'check_waiting' and pg_temp.fx('fay') <> pg_temp.fx('aff')
    and (select (referred_by, referral_source, referral_code_used) is not distinct from (null::uuid, null::text, null::text)
           from customers where id = pg_temp.fx('fay'))
    and exists (select 1 from referral_signup_checks k where k.customer_id = pg_temp.fx('fay') and k.status = 'pending'
                  and k.referrer_customer_id = pg_temp.fx('aff') and k.phone_shared_with = array[pg_temp.fx('aff')])
    and exists (select 1 from referral_signup_events e where e.new_customer_id = pg_temp.fx('fay') and e.outcome = 'phone_shared')
    and pg_temp.self_audits((pg_temp.fs('fs3', 5)).id) = 0
    and public.event_web_referral_note((pg_temp.fs('fs3', 5)).id) = pg_temp.waiting_note('phone', 'Aff Testlink', pg_temp.tx('code_ok')),
  'FS6 staff make a customer of the one on the affiliate''s own phone: no referrer yet, a pending check naming the affiliate, the note says it waits (the owner ~20:15): ' || pg_temp.tx('fs6_fay'));
select pg_temp.check(pg_temp.tx('fs6_gee') = 'ok' and (pg_temp.fs('fs4', 1)).match = 'staff_attached'
    and (pg_temp.fs('fs4', 1)).customer_id = pg_temp.fx('gail') and (pg_temp.fs('fs4', 1)).referral_outcome = 'self'
    and (pg_temp.fs('fs4', 1)).referral_self_by = array['customer', 'email']
    and (select (referred_by, email) from customers where id = pg_temp.fx('gail')) = (null::uuid, 'gail.self.ht' || lower(pg_temp.tx('sfx')) || '@gmail.com')
    and not exists (select 1 from referral_signup_events e where e.referrer_customer_id = pg_temp.fx('gail'))
    and pg_temp.self_audits((pg_temp.fs('fs4', 1)).id) = 1
    and exists (select 1 from audit_logs a where a.record_id = (pg_temp.fs('fs4', 1)).id and a.action = 'event_registration_matched'
                  and a.new_data @> '{"referral_outcome": "self"}'::jsonb),
  'FS6 staff attach the held one to the affiliate''s own record: self, no event, her record as it was, the note written once: ' || pg_temp.tx('fs6_gee'));
-- FS7 VIP paid while she is held (the owner, 21 Oct 2026): the affiliate (FS1, held under her name) and Rina pay together;
-- the payment waits until staff match her; linked to her own record, her VIP is hers and earns her own referrer (her
-- upline) tier-1 as usual, once, and her nothing; Rina's, on the same payment, earns the affiliate's as usual.
select pg_temp.put('fs7c', pg_temp.checkout('live', 'fs7', array[pg_temp.tok(pg_temp.tx('fs1')::jsonb, 1), pg_temp.tok(pg_temp.tx('fs3')::jsonb, 2)])::text);
select pg_temp.put('fs7p', pg_temp.paid('live', 'fs7', array[pg_temp.tok(pg_temp.tx('fs1')::jsonb, 1), pg_temp.tok(pg_temp.tx('fs3')::jsonb, 2)], 14400)::text);
select pg_temp.put('fs7_wait', (pg_temp.vorder('fs7')).status || ' ' || (pg_temp.vorder('fs7')).waiting_for_match
                               || ' ' || (select count(*) from pg_temp.vinvoices('fs7')));
select pg_temp.as_user('staff');
select pg_temp.put('fs7_att', pg_temp.err(format('select public.event_registration_attach(%L, %L, %L)', (pg_temp.fs('fs1', 1)).id,
  pg_temp.fx('aff'), 'The affiliate herself, on a new number')));
select pg_temp.as_user('owner');
create function pg_temp.fs_comm(tag text, cust uuid) returns jsonb language sql as
$$ select coalesce(jsonb_agg(jsonb_build_array(c.tier::text, c.referrer_customer_id, c.commission_amount) order by c.tier::text, c.referrer_customer_id), '[]'::jsonb)
     from commissions c join pg_temp.vinvoices(tag) i on i.id = c.invoice_id where i.customer_id = cust $$;
select pg_temp.check((pg_temp.tx('fs7p')::jsonb)->>'status' = 'needs_review' and pg_temp.tx('fs7_wait') = 'needs_review true 0'
    and pg_temp.tx('fs7_att') = 'ok'
    and (pg_temp.fs('fs1', 1)).match = 'staff_attached' and (pg_temp.fs('fs1', 1)).customer_id = pg_temp.fx('aff')
    and (pg_temp.fs('fs1', 1)).referral_outcome = 'self' and (pg_temp.fs('fs1', 1)).referral_self_by = array['customer', 'name']
    and pg_temp.self_audits((pg_temp.fs('fs1', 1)).id) = 1
    and (pg_temp.vorder('fs7')).status = 'invoiced'
    and (select count(*) from pg_temp.vinvoices('fs7') i where i.status = 'paid') = 2
    and (select referred_by from customers where id = pg_temp.fx('aff')) = pg_temp.fx('upline')
    and not exists (select 1 from referral_signup_events e where e.normalized_phone = pg_temp.ph(200))
    and pg_temp.fs_comm('fs7', pg_temp.fx('aff')) = jsonb_build_array(jsonb_build_array('tier1', pg_temp.fx('upline'), 10.80))
    and pg_temp.fs_comm('fs7', pg_temp.fx('rina'))
        = jsonb_build_array(jsonb_build_array('tier1', pg_temp.fx('aff'), 10.80), jsonb_build_array('tier2', pg_temp.fx('upline'), 0.54))
    and public.event_web_referral_note((pg_temp.fs('fs1', 1)).id) = pg_temp.self_note('customer', 'Aff Testlink', pg_temp.tx('code_ok')),
  'FS7 VIP paid while the affiliate was held under her name (the owner, 21 Oct 2026): the payment waits; staff link her own record: her VIP earns her upline tier-1 (S$10.80) once and her nothing; Rina''s, on the same payment, earns the affiliate''s as usual; her note: she earns no commission from it: ' || pg_temp.tx('fs7_wait'));
-- FS7b someone else with her name (the same words) on a new phone and email, VIP paid while held: staff make a new
-- customer: not referred through the link, and their VIP earns nobody anything.
select pg_temp.put('fs7b', pg_temp.register('live', 'fs7b', jsonb_build_array(
  pg_temp.person(1, 'Aff', 'Testlink', pg_temp.ph(205), pg_temp.mail('fs7b'), array[pg_temp.d(8)])), pg_temp.tx('code_ok'))::text);
select pg_temp.put('fs7bc', pg_temp.checkout('live', 'fs7b', array[pg_temp.tok(pg_temp.tx('fs7b')::jsonb, 1)])::text);
select pg_temp.put('fs7bp', pg_temp.paid('live', 'fs7b', array[pg_temp.tok(pg_temp.tx('fs7b')::jsonb, 1)], 7200)::text);
select pg_temp.as_user('staff');
select pg_temp.put('fs7b_make', pg_temp.err(format('select public.event_registration_create_customer(%L, %L)', (pg_temp.fs('fs7b', 1)).id,
  'Another Aff Testlink: a different birthday and address')));
select pg_temp.putx('fs7b_cust', (pg_temp.fs('fs7b', 1)).customer_id);
select pg_temp.as_user('owner');
select pg_temp.check((pg_temp.fs('fs7b', 1)).hold_reason = 'affiliate_name' and (pg_temp.tx('fs7bp')::jsonb)->>'status' = 'needs_review'
    and pg_temp.tx('fs7b_make') = 'ok' and (pg_temp.fs('fs7b', 1)).match = 'staff_created'
    and pg_temp.fx('fs7b_cust') is not null and pg_temp.fx('fs7b_cust') <> pg_temp.fx('aff')
    and (pg_temp.fs('fs7b', 1)).referral_outcome = 'self' and (pg_temp.fs('fs7b', 1)).referral_self_by = array['name']
    and (select (c.referred_by, c.referral_source, c.referral_code_used) is not distinct from (null::uuid, null::text, null::text)
           from customers c where c.id = pg_temp.fx('fs7b_cust'))
    and not exists (select 1 from referral_signup_events e where e.new_customer_id = pg_temp.fx('fs7b_cust') or e.normalized_phone = pg_temp.ph(205))
    and not exists (select 1 from referral_signup_checks k where k.customer_id = pg_temp.fx('fs7b_cust'))
    and (pg_temp.vorder('fs7b')).status = 'invoiced'
    and (select count(*) from pg_temp.vinvoices('fs7b') i where i.status = 'paid' and i.customer_id = pg_temp.fx('fs7b_cust')) = 1
    and pg_temp.fs_comm('fs7b', pg_temp.fx('fs7b_cust')) = '[]'::jsonb
    and public.event_web_referral_note((pg_temp.fs('fs7b', 1)).id) = pg_temp.self_other_note('name', 'Aff Testlink', pg_temp.tx('code_ok')),
  'FS7b someone else with her name, VIP paid while held, made a new customer by staff: not referred (no referrer, event or check), their VIP invoiced to them earns nobody anything, and the note says so (the owner, 21 Oct 2026): ' || pg_temp.tx('fs7b_make'));
-- FS8 the test key says the same and writes no audit row.
select pg_temp.put('fs8', pg_temp.register('test', 'fs8', jsonb_build_array(
  pg_temp.person(1, 'Testlink', 'Aff', pg_temp.ph(204), pg_temp.mail('fs8'), array[pg_temp.d(7)])), pg_temp.tx('code_ok'))::text);
select pg_temp.as_user('owner');
select pg_temp.put('fs8_tab', public.event_web_settings_get(pg_temp.fx('ev'))::text);
select pg_temp.check((pg_temp.fs('fs8', 1)).test_outcome = '{"match": "held", "hold_reason": "affiliate_name", "referral": "self"}'::jsonb
    and pg_temp.self_audits((pg_temp.fs('fs8', 1)).id) = 0
    and not exists (select 1 from customers c where public.normalize_customer_phone(c.phone) = pg_temp.ph(204))
    and exists (select 1 from jsonb_array_elements(pg_temp.tx('fs8_tab')::jsonb->'test'->'registrations') r,
                              jsonb_array_elements(r->'people') p
                 where r->>'registration_id' = pg_temp.bid('REG', 'fs8')
                   and p->>'referral_note' = pg_temp.self_note('name', 'Aff Testlink', pg_temp.tx('code_ok'))),
  'FS8 the test key: what a live key would have done says held under her name, not referred; the Website tab shows the note, nothing is written');

-- FS9 (the review of round 4, RV13) someone else's existing record is not her. Zoe is an affiliate; Hal, on
-- her phone, is already her referral; Ivy is a customer. Hal through Zoe's link is already a customer (a
-- duplicate event, his referrer kept, a note saying so: the owner ~20:15, D) and his VIP still pays her, as
-- any purchase of his does. Ivy, typed on a new phone with Zoe's email, is held (not "self": the owner
-- ~20:15, A) until staff attach her to her own record: then already a customer, with a note.
select pg_temp.as_user('owner');
do $$ declare c uuid; d uuid; i uuid; begin
  insert into customers(full_name, phone, email) values ('Zoe Selfnine', pg_temp.ph(220), pg_temp.mail('fs9zoe')) returning id into c;
  insert into customer_affiliates(customer_id, status, referral_code) values (c, 'active', 'HZ' || pg_temp.tx('sfx'));
  insert into customers(full_name, phone, email) values ('Hal Selfnine', pg_temp.ph(220), pg_temp.mail('fs9hal')) returning id into d;
  update customers set referred_by = c where id = d;
  insert into customers(full_name, phone, email) values ('Ivy Otherhouse', pg_temp.ph(222), pg_temp.mail('fs9ivy')) returning id into i;
  insert into fx values ('fs9_zoe', c), ('fs9_hal', d), ('fs9_ivy', i);
  insert into tx values ('code_zoe', 'HZ' || pg_temp.tx('sfx'));
end $$;
select pg_temp.put('fs9', pg_temp.register('live', 'fs9', jsonb_build_array(
  pg_temp.person(1, 'Hal', 'Selfnine', pg_temp.ph(220), pg_temp.mail('fs9hal'), array[pg_temp.d(7)]),
  pg_temp.person(2, 'Ivy', 'Otherhouse', pg_temp.ph(221), upper(pg_temp.mail('fs9zoe')), array[pg_temp.d(8)])), pg_temp.tx('code_zoe'))::text);
select pg_temp.check((pg_temp.fs('fs9', 1)).match = 'exact' and (pg_temp.fs('fs9', 1)).customer_id = pg_temp.fx('fs9_hal')
    and (pg_temp.fs('fs9', 1)).referral_outcome = 'already_customer' and (pg_temp.fs('fs9', 1)).referral_self_by is null
    and public.event_web_referral_note((pg_temp.fs('fs9', 1)).id) = pg_temp.existing_note(pg_temp.tx('code_zoe'), 'Zoe Selfnine')
    and pg_temp.self_audits((pg_temp.fs('fs9', 1)).id) = 0
    and (select count(*) from referral_signup_events e where e.normalized_phone = pg_temp.ph(220) and e.outcome = 'duplicate'
            and e.referral_code = pg_temp.tx('code_zoe') and e.referrer_customer_id = pg_temp.fx('fs9_zoe')) = 1
    and (select referred_by from customers where id = pg_temp.fx('fs9_hal')) = pg_temp.fx('fs9_zoe'),
  'FS9 Hal (already Zoe''s referral, on her phone) through her link: already a customer, a duplicate event, his referrer kept; the note says so (the owner ~20:15, D)');
select pg_temp.check((pg_temp.fs('fs9', 2)).match = 'held' and (pg_temp.fs('fs9', 2)).hold_reason = 'email_in_use'
    and (pg_temp.fs('fs9', 2)).referral_outcome = 'held' and (pg_temp.fs('fs9', 2)).referral_self_by is null
    and public.event_web_referral_note((pg_temp.fs('fs9', 2)).id) = pg_temp.shares_note('email inbox', 'Zoe Selfnine', pg_temp.tx('code_zoe'))
    and pg_temp.self_audits((pg_temp.fs('fs9', 2)).id) = 0,
  'FS9 Ivy on a new phone with Zoe''s email: held for staff, the referral waits, not treated as Zoe (the owner ~20:15)');
select pg_temp.as_user('staff');
select pg_temp.put('fs9_att', pg_temp.err(format('select public.event_registration_attach(%L, %L, %L)', (pg_temp.fs('fs9', 2)).id, pg_temp.fx('fs9_ivy'), 'Ivy herself, a new number, typed her friend''s email')));
select pg_temp.put('fs9_x', public.event_web_guest_extras(pg_temp.fx('ev'))::text);
select pg_temp.check(pg_temp.tx('fs9_att') = 'ok' and (pg_temp.fs('fs9', 2)).match = 'staff_attached'
    and (pg_temp.fs('fs9', 2)).customer_id = pg_temp.fx('fs9_ivy') and (pg_temp.fs('fs9', 2)).referral_outcome = 'already_customer'
    and (pg_temp.fs('fs9', 2)).referral_self_by is null
    and public.event_web_referral_note((pg_temp.fs('fs9', 2)).id) = pg_temp.existing_note(pg_temp.tx('code_zoe'), null)
    and pg_temp.self_audits((pg_temp.fs('fs9', 2)).id) = 0
    and (select (referred_by, email) from customers where id = pg_temp.fx('fs9_ivy')) = (null::uuid, pg_temp.mail('fs9ivy'))
    and exists (select 1 from referral_signup_events e where e.normalized_phone = pg_temp.ph(221) and e.outcome = 'duplicate'
                  and e.referrer_customer_id = pg_temp.fx('fs9_zoe'))
    and exists (select 1 from audit_logs a where a.record_id = (pg_temp.fs('fs9', 2)).id and a.action = 'event_registration_matched'
                  and a.new_data @> '{"referral_outcome": "already_customer"}'::jsonb),
  'FS9 staff attach Ivy to her own record: already a customer (a duplicate event), not referred, the note says so: ' || pg_temp.tx('fs9_att'));
select pg_temp.check(
    (select g->'referral' from jsonb_array_elements(pg_temp.tx('fs9_x')::jsonb->'guests') g
      where (g->>'guest_id')::uuid = (pg_temp.fs('fs9', 1)).free_guest_id)
      @> jsonb_build_object('code', pg_temp.tx('code_zoe'), 'outcome', 'already_customer',
                            'note', pg_temp.existing_note(pg_temp.tx('code_zoe'), 'Zoe Selfnine'))
    and (select g->'referral' from jsonb_array_elements(pg_temp.tx('fs9_x')::jsonb->'guests') g
          where (g->>'guest_id')::uuid = (pg_temp.fs('fs9', 2)).free_guest_id)
      @> jsonb_build_object('code', pg_temp.tx('code_zoe'), 'outcome', 'already_customer',
                            'note', pg_temp.existing_note(pg_temp.tx('code_zoe'), null)),
  'FS9 the Guests tab: already a customer, with the plain note (his referral by Zoe stands; Ivy had none, none added), not "No commission"');
select pg_temp.put('fs9c', pg_temp.checkout('live', 'fs9', array[pg_temp.tok(pg_temp.tx('fs9')::jsonb, 1)])::text);
select pg_temp.put('fs9p', pg_temp.paid('live', 'fs9', array[pg_temp.tok(pg_temp.tx('fs9')::jsonb, 1)], 7200)::text);
select pg_temp.check((pg_temp.tx('fs9p')::jsonb)->>'status' = 'invoiced'
    and (select count(*) from pg_temp.vinvoices('fs9') i where i.status = 'paid' and i.customer_id = pg_temp.fx('fs9_hal')) = 1
    and (select jsonb_agg(jsonb_build_array(c.tier::text, c.referrer_customer_id, c.commission_amount) order by c.tier::text)
           from commissions c join pg_temp.vinvoices('fs9') i on i.id = c.invoice_id)
        = jsonb_build_array(jsonb_build_array('tier1', pg_temp.fx('fs9_zoe'), 10.80)),
  'FS9 Hal''s VIP earns Zoe her tier-1 commission, as his referral already did (nothing new from this registration): ' || pg_temp.tx('fs9p'));
-- The test key says the same for someone else's record.
select pg_temp.put('fs9t', pg_temp.register('test', 'fs9t', jsonb_build_array(
  pg_temp.person(1, 'Hal', 'Selfnine', pg_temp.ph(220), pg_temp.mail('fs9hal'), array[pg_temp.d(7)])), pg_temp.tx('code_zoe'))::text);
select pg_temp.check((pg_temp.fs('fs9t', 1)).test_outcome = '{"match": "exact", "hold_reason": null, "referral": "already_customer"}'::jsonb
    and (pg_temp.fs('fs9t', 1)).referral_self_by is null and pg_temp.self_audits((pg_temp.fs('fs9t', 1)).id) = 0
    and public.event_web_referral_note((pg_temp.fs('fs9t', 1)).id) = pg_temp.existing_note(pg_temp.tx('code_zoe'), '?'),
  'FS9 the test key: Hal through Zoe''s link would be already a customer, with no mark (the note: any referral they have stands)');
select pg_temp.as_user('owner');
-- FS10 (the review of 21 Oct 2026) Aff Paused, whose link is switched off (suspended), through her own link: her name
-- (other words, and the same words) on new phones and emails is held for staff as on a live link, nobody referred;
-- her VIP paid while held waits; staff link her record: herself, and the VIP earns her upline as usual (C); the other,
-- made a new customer by staff, is not referred and their VIP earns nothing; the notes name the link as switched off;
-- the test key says the same and writes nothing. Linked to her record, her row reads 'self' (the owner, 21 Oct 2026, R6-6).
select pg_temp.putx('paused', (select customer_id from customer_affiliates where referral_code = pg_temp.tx('code_off')));
update customers set referred_by = pg_temp.fx('upline') where id = pg_temp.fx('paused');
create function pg_temp.off_link() returns text language sql as $$ select pg_temp.tx('code_off') || ', switched off' $$;
select pg_temp.put('fs10', pg_temp.register('live', 'fs10', jsonb_build_array(
  pg_temp.person(1, 'Paused', 'Aff', pg_temp.ph(270), pg_temp.mail('fs10-1'), array[pg_temp.d(7)]),
  pg_temp.person(2, 'Aff', 'Paused', pg_temp.ph(271), pg_temp.mail('fs10-2'), array[pg_temp.d(8)])), pg_temp.tx('code_off'))::text);
select pg_temp.check((pg_temp.tx('fs10')::jsonb)->>'status' = 'registered' and not pg_temp.says_who(pg_temp.tx('fs10')::jsonb)
    and (select count(*) filter (where p.match = 'held' and p.hold_reason = 'affiliate_name'
                                   and p.candidate_customer_ids = array[pg_temp.fx('paused')] and p.customer_id is null
                                   and p.referral_outcome = 'link_off' and p.referral_self_by = array['name']
                                   and (pg_temp.guest(p.free_guest_id)).status = 'registered' and pg_temp.self_audits(p.id) = 1
                                   and public.event_web_referral_note(p.id) = pg_temp.self_note('name', 'Aff Paused', pg_temp.off_link()))
           from event_registration_people p where p.id in ((pg_temp.fs('fs10', 1)).id, (pg_temp.fs('fs10', 2)).id)) = 2
    and not exists (select 1 from customers c where public.normalize_customer_phone(c.phone) in (pg_temp.ph(270), pg_temp.ph(271)))
    and not exists (select 1 from referral_signup_events e where e.normalized_phone in (pg_temp.ph(270), pg_temp.ph(271))),
  'FS10 through her own link switched off, the affiliate''s name (other words, or the same) on a new phone and email: on the guest list, held for staff with her record to link (as on a live link), no customer made, nobody referred; the note names the link as switched off: '
  || coalesce(public.event_web_referral_note((pg_temp.fs('fs10', 1)).id), '(none)'));
select pg_temp.put('fs10c', pg_temp.checkout('live', 'fs10', array[pg_temp.tok(pg_temp.tx('fs10')::jsonb, 1)])::text);
select pg_temp.put('fs10p', pg_temp.paid('live', 'fs10', array[pg_temp.tok(pg_temp.tx('fs10')::jsonb, 1)], 7200)::text);
select pg_temp.as_user('staff');
select pg_temp.put('fs10_att', pg_temp.err(format('select public.event_registration_attach(%L, %L, %L)', (pg_temp.fs('fs10', 1)).id,
  pg_temp.fx('paused'), 'The affiliate herself, on a new number')));
select pg_temp.put('fs10_make', pg_temp.err(format('select public.event_registration_create_customer(%L, %L)', (pg_temp.fs('fs10', 2)).id,
  'Another Aff Paused: a different birthday')));
select pg_temp.as_user('owner');
select pg_temp.putx('fs10_other', (pg_temp.fs('fs10', 2)).customer_id);
select pg_temp.put('fs10bc', pg_temp.checkout('live', 'fs10b', array[pg_temp.tok(pg_temp.tx('fs10')::jsonb, 2)])::text);
select pg_temp.put('fs10bp', pg_temp.paid('live', 'fs10b', array[pg_temp.tok(pg_temp.tx('fs10')::jsonb, 2)], 7200)::text);
select pg_temp.check((pg_temp.tx('fs10p')::jsonb)->>'status' = 'needs_review' and pg_temp.tx('fs10_att') = 'ok'
    and (pg_temp.fs('fs10', 1)).match = 'staff_attached' and (pg_temp.fs('fs10', 1)).customer_id = pg_temp.fx('paused')
    and (pg_temp.fs('fs10', 1)).referral_outcome = 'self' and (pg_temp.fs('fs10', 1)).referral_self_by = array['customer', 'name']
    and pg_temp.self_audits((pg_temp.fs('fs10', 1)).id) = 1
    and (pg_temp.vorder('fs10')).status = 'invoiced'
    and (select count(*) from pg_temp.vinvoices('fs10') i where i.status = 'paid' and i.customer_id = pg_temp.fx('paused')) = 1
    and (select referred_by from customers where id = pg_temp.fx('paused')) = pg_temp.fx('upline')
    and pg_temp.fs_comm('fs10', pg_temp.fx('paused')) = jsonb_build_array(jsonb_build_array('tier1', pg_temp.fx('upline'), 10.80))
    and public.event_web_referral_note((pg_temp.fs('fs10', 1)).id) = pg_temp.self_note('customer', 'Aff Paused', pg_temp.off_link()),
  'FS10 her VIP paid while held waits; staff link her own record: herself (self, as on a live link: R6-6; not referred), the VIP earns her upline tier-1 (S$10.80) once and her nothing; her note: she earns no commission from it: '
  || pg_temp.tx('fs10_att') || ' ' || pg_temp.fs_comm('fs10', pg_temp.fx('paused'))::text);
select pg_temp.check(pg_temp.tx('fs10_make') = 'ok' and (pg_temp.fs('fs10', 2)).match = 'staff_created'
    and pg_temp.fx('fs10_other') is not null and pg_temp.fx('fs10_other') <> pg_temp.fx('paused')
    and (pg_temp.fs('fs10', 2)).referral_outcome = 'link_off' and (pg_temp.fs('fs10', 2)).referral_self_by = array['name']
    and (select (c.referred_by, c.referral_source, c.referral_code_used) is not distinct from (null::uuid, null::text, null::text)
           from customers c where c.id = pg_temp.fx('fs10_other'))
    and not exists (select 1 from referral_signup_checks k where k.customer_id = pg_temp.fx('fs10_other'))
    and (pg_temp.tx('fs10bp')::jsonb)->>'status' = 'invoiced'
    and pg_temp.fs_comm('fs10b', pg_temp.fx('fs10_other')) = '[]'::jsonb
    and public.event_web_referral_note((pg_temp.fs('fs10', 2)).id) = pg_temp.self_other_note('name', 'Aff Paused', pg_temp.off_link()),
  'FS10 someone else with her name, made a new customer by staff: no referrer, no check, their VIP earns nobody anything; the note says so: '
  || pg_temp.tx('fs10_make') || ' ' || coalesce((pg_temp.tx('fs10bp')::jsonb)->>'status', '?'));
select pg_temp.put('fs10t', pg_temp.register('test', 'fs10t', jsonb_build_array(
  pg_temp.person(1, 'Paused', 'Aff', pg_temp.ph(272), pg_temp.mail('fs10t'), array[pg_temp.d(7)])), pg_temp.tx('code_off'))::text);
select pg_temp.check((pg_temp.fs('fs10t', 1)).test_outcome = '{"match": "held", "hold_reason": "affiliate_name", "referral": "link_off"}'::jsonb
    and pg_temp.self_audits((pg_temp.fs('fs10t', 1)).id) = 0
    and not exists (select 1 from customers c where public.normalize_customer_phone(c.phone) = pg_temp.ph(272))
    and public.event_web_referral_note((pg_temp.fs('fs10t', 1)).id) = pg_temp.self_note('name', 'Aff Paused', pg_temp.off_link()),
  'FS10 the test key says the same (held under her name, her link switched off) and writes nothing');
-- (the review of round 7, 21 Oct 2026) Aff Paused on her own phone through her own switched-off link: matched straight
-- away on her own record, she is herself: self, as on a live link and as when staff link her (R6-6); the test key the same.
select pg_temp.put('fs10x', pg_temp.register('live', 'fs10x', jsonb_build_array(
  pg_temp.person(1, 'Aff', 'Paused', pg_temp.ph(902), null, array[pg_temp.d(7)])), pg_temp.tx('code_off'))::text);
select pg_temp.put('fs10xt', pg_temp.register('test', 'fs10xt', jsonb_build_array(
  pg_temp.person(1, 'Aff', 'Paused', pg_temp.ph(902), null, array[pg_temp.d(7)])), pg_temp.tx('code_off'))::text);
select pg_temp.check((pg_temp.tx('fs10x')::jsonb)->>'status' = 'registered' and not pg_temp.says_who(pg_temp.tx('fs10x')::jsonb)
    and (pg_temp.fs('fs10x', 1)).match = 'exact' and (pg_temp.fs('fs10x', 1)).customer_id = pg_temp.fx('paused')
    and (pg_temp.fs('fs10x', 1)).referral_outcome = 'self'
    and (pg_temp.fs('fs10x', 1)).referral_self_by @> array['customer', 'name']
    and pg_temp.self_audits((pg_temp.fs('fs10x', 1)).id) = 1
    and public.event_web_referral_note((pg_temp.fs('fs10x', 1)).id) = pg_temp.self_note('customer', 'Aff Paused', pg_temp.off_link())
    and (pg_temp.fs('fs10xt', 1)).test_outcome = '{"match": "exact", "hold_reason": null, "referral": "self"}'::jsonb
    and pg_temp.self_audits((pg_temp.fs('fs10xt', 1)).id) = 0,
  'FS10 her own phone through her own switched-off link: matched on her own record, self with her note (as on a live link, R6-6), not link_off; the test key says self and writes nothing: '
  || coalesce((pg_temp.fs('fs10x', 1)).referral_outcome, '?') || ' ' || coalesce(public.event_web_referral_note((pg_temp.fs('fs10x', 1)).id), '(none)'));

-- ═════ FA The owner's answers, 20 Oct 2026, ~20:15 ═════
-- A  Someone with another name through an affiliate's link on her own phone or
--    email inbox (her mother, a friend she registered) is not her: held for
--    staff; made a customer, they become her referral only once an Owner or
--    Manager checks them as a different person (425's check, Q19 = A), and
--    no commission comes before that (on VIP only: a VIP already paid earns
--    then). Checked as the same person: never referred.
-- B  Her name in the same words is still her, on any phone and email.
-- C  Her own referrer (upline) still earns on her own VIP.
-- D  An existing customer through her link keeps any referral they have and
--    is not referred again; staff see a plain note.
-- One form mixes them all; the test key says the same and writes nothing.
select pg_temp.as_user('owner');
do $$ declare u uuid; a uuid; e uuid; begin
  insert into customers(full_name, phone) values ('Uma Upline', pg_temp.ph(241)) returning id into u;
  insert into customers(full_name, phone, email)
  values ('Rhea Linkowner', pg_temp.ph(240), 'rhea.link.ht' || lower(pg_temp.tx('sfx')) || '@gmail.com') returning id into a;
  update customers set referred_by = u where id = a;
  insert into customer_affiliates(customer_id, status, referral_code) values (a, 'active', 'HR' || pg_temp.tx('sfx'));
  -- An existing customer whom another affiliate (Gail) already referred.
  insert into customers(full_name, phone, email) values ('Ella Elsewhere', pg_temp.ph(242), pg_temp.mail('fa-ella')) returning id into e;
  update customers set referred_by = pg_temp.fx('gail') where id = e;
  insert into fx values ('fa_rhea', a), ('fa_uma', u), ('fa_ella', e);
  insert into tx values ('code_rhea', 'HR' || pg_temp.tx('sfx'));
  insert into referral_campaigns(code, title, reward_reason, starts_on, ends_on, tiers)
  values ('HT436FA' || pg_temp.tx('sfx'), 'HT436 FA ' || pg_temp.tx('sfx'), 'HT436 check', pg_temp.d(-1), pg_temp.d(30), array[3])
  returning id into u;
  insert into fx values ('fa_campaign', u);
end $$;
create function pg_temp.fa(tag text, pos int) returns public.event_registration_people language sql as
$$ select pg_temp.pp(pg_temp.pid(pg_temp.tx(tag)::jsonb, pos)) $$;
create function pg_temp.fa_people(tag text, phones int[]) returns jsonb language sql as
$$ select jsonb_build_array(
     pg_temp.person(1, 'Linkowner', 'Rhea', pg_temp.ph(phones[1]), pg_temp.mail(tag || '-1'), array[pg_temp.d(7)]),
     pg_temp.person(2, 'Mona', 'Mother', pg_temp.ph(240), pg_temp.mail(tag || '-2'), array[pg_temp.d(7)]),
     pg_temp.person(3, 'Frida', 'Friend', pg_temp.ph(phones[2]), 'RheaLinkHT' || pg_temp.tx('sfx') || '+seminar@googlemail.com', array[pg_temp.d(8)]),
     pg_temp.person(4, 'Ella', 'Elsewhere', pg_temp.ph(242), pg_temp.mail(tag || '-4'), array[pg_temp.d(7)]),
     pg_temp.person(5, 'Nico', 'Newperson', pg_temp.ph(phones[3]), pg_temp.mail(tag || '-5'), array[pg_temp.d(7)]),
     pg_temp.person(6, 'Rhea', 'Linkowner', pg_temp.ph(phones[4]), 'rhea.link.ht' || lower(pg_temp.tx('sfx')) || '@gmail.com', array[pg_temp.d(8)])) $$;
create function pg_temp.fa_comm(inv uuid) returns jsonb language sql as
$$ select coalesce(jsonb_agg(jsonb_build_array(c.tier::text, c.referrer_customer_id, c.commission_amount) order by c.tier::text), '[]'::jsonb)
     from commissions c where c.invoice_id = inv $$;
create function pg_temp.fa_inv(tag text, person uuid) returns uuid language sql as
$$ select i.id from pg_temp.vinvoices(tag) i join public.event_vip_order_people op on op.invoice_id = i.id where op.person_id = person $$;
create function pg_temp.fa_check(cust uuid) returns public.referral_signup_checks language sql as
$$ select * from referral_signup_checks where customer_id = cust $$;
-- FA1 the form: the affiliate under her name in other words (new phone and email), her mother on her phone,
-- a friend she registered with her own Gmail inbox, a customer Gail already referred, a new person, and the
-- affiliate herself under her own name on a new phone with her own email.
select pg_temp.put('fa1', pg_temp.register('live', 'fa1', pg_temp.fa_people('fa1', array[243, 244, 245, 246]), pg_temp.tx('code_rhea'))::text);
-- The test key, straight away, says what a live key would have done (other phones for the new people).
select pg_temp.put('fa1t', pg_temp.register('test', 'fa1t', pg_temp.fa_people('fa1t', array[247, 248, 249, 250]), pg_temp.tx('code_rhea'))::text);
select pg_temp.check((pg_temp.tx('fa1')::jsonb)->>'status' = 'registered' and not pg_temp.says_who(pg_temp.tx('fa1')::jsonb)
    and (select array_agg(k order by k) from jsonb_object_keys(pg_temp.tx('fa1')::jsonb) k) = array['ok', 'people', 'registration_id', 'status', 'test']
    and (select count(*) from jsonb_array_elements(pg_temp.tx('fa1')::jsonb->'people') x
          where x->>'already_registered' = 'false' and x->>'vip' = 'none') = 6,
  'FA1 the form is registered, six people, and the answer says nothing of who was matched, held or referred');
select pg_temp.putx('fa_nico', (pg_temp.fa('fa1', 5)).customer_id);
select pg_temp.check((pg_temp.fa('fa1', 1)).match = 'held' and (pg_temp.fa('fa1', 1)).hold_reason = 'affiliate_name'
    and (pg_temp.fa('fa1', 1)).candidate_customer_ids = array[pg_temp.fx('fa_rhea')]
    and (pg_temp.fa('fa1', 1)).customer_id is null and (pg_temp.fa('fa1', 1)).referral_outcome = 'self'
    and (pg_temp.fa('fa1', 1)).referral_self_by = array['name']
    and not exists (select 1 from customers c where public.normalize_customer_phone(c.phone) = pg_temp.ph(243))
    and not exists (select 1 from referral_signup_events e where e.normalized_phone = pg_temp.ph(243))
    and (pg_temp.fa('fa1', 6)).match = 'held' and (pg_temp.fa('fa1', 6)).hold_reason = 'email_in_use'
    and (pg_temp.fa('fa1', 6)).referral_outcome = 'self' and (pg_temp.fa('fa1', 6)).referral_self_by = array['name', 'email']
    and pg_temp.self_audits((pg_temp.fa('fa1', 1)).id) = 1 and pg_temp.self_audits((pg_temp.fa('fa1', 6)).id) = 1,
  'FA1 (B) the affiliate is still herself by her name: in other words on a new phone and email (held for staff with her record to link, the owner 21 Oct 2026; nobody''s referral); under her own name on a new phone with her own email (held, self by name and email inbox)');
select pg_temp.check((pg_temp.fa('fa1', 2)).match = 'held' and (pg_temp.fa('fa1', 2)).hold_reason = 'phone_in_use'
    and (pg_temp.fa('fa1', 2)).candidate_customer_ids = array[pg_temp.fx('fa_rhea')]
    and (pg_temp.fa('fa1', 2)).referral_outcome = 'held' and (pg_temp.fa('fa1', 2)).referral_self_by is null
    and public.event_web_affiliate_contact((pg_temp.fa('fa1', 2)).id) = array['phone']
    and (pg_temp.fa('fa1', 3)).match = 'held' and (pg_temp.fa('fa1', 3)).hold_reason = 'email_in_use'
    and (pg_temp.fa('fa1', 3)).candidate_customer_ids = array[pg_temp.fx('fa_rhea')]
    and (pg_temp.fa('fa1', 3)).referral_outcome = 'held' and (pg_temp.fa('fa1', 3)).referral_self_by is null
    and public.event_web_affiliate_contact((pg_temp.fa('fa1', 3)).id) = array['email']
    and pg_temp.self_audits((pg_temp.fa('fa1', 2)).id) = 0 and pg_temp.self_audits((pg_temp.fa('fa1', 3)).id) = 0
    and (pg_temp.guest((pg_temp.fa('fa1', 2)).free_guest_id)).status = 'registered'
    and (pg_temp.guest((pg_temp.fa('fa1', 3)).free_guest_id)).status = 'registered',
  'FA1 (A) her mother on her phone and her friend on her Gmail inbox (another name each): held for staff, the referral waits, not "self"; both on the guest list');
select pg_temp.check((pg_temp.fa('fa1', 4)).match = 'exact' and (pg_temp.fa('fa1', 4)).customer_id = pg_temp.fx('fa_ella')
    and (pg_temp.fa('fa1', 4)).referral_outcome = 'already_customer' and (pg_temp.fa('fa1', 4)).referral_self_by is null
    and (select referred_by from customers where id = pg_temp.fx('fa_ella')) = pg_temp.fx('gail')
    and exists (select 1 from referral_signup_events e where e.normalized_phone = pg_temp.ph(242) and e.outcome = 'duplicate'
                  and e.referrer_customer_id = pg_temp.fx('fa_rhea'))
    and not exists (select 1 from referral_signup_checks k where k.customer_id = pg_temp.fx('fa_ella')),
  'FA1 (D) a customer Gail already referred, through Rhea''s link: already a customer, not referred again, Gail''s referral kept');
select pg_temp.check((pg_temp.fa('fa1', 5)).match = 'new_customer' and (pg_temp.fa('fa1', 5)).referral_outcome = 'created'
    and (select referred_by from customers where id = pg_temp.fx('fa_nico')) = pg_temp.fx('fa_rhea'),
  'FA1 a new person on the same form is Rhea''s referral as usual');
select pg_temp.check(
    (select jsonb_agg(p.test_outcome order by p.position) from event_registration_people p
      join event_registrations r on r.id = p.registration_ref where r.registration_id = pg_temp.bid('REG', 'fa1t'))
    = '[{"match": "held", "hold_reason": "affiliate_name", "referral": "self"},
        {"match": "held", "hold_reason": "phone_in_use", "referral": "held"},
        {"match": "held", "hold_reason": "email_in_use", "referral": "held"},
        {"match": "exact", "hold_reason": null, "referral": "already_customer"},
        {"match": "new_customer", "hold_reason": null, "referral": "created"},
        {"match": "held", "hold_reason": "email_in_use", "referral": "self"}]'::jsonb
    and not exists (select 1 from customers c where public.normalize_customer_phone(c.phone) in (pg_temp.ph(247), pg_temp.ph(248), pg_temp.ph(249), pg_temp.ph(250)))
    and not exists (select 1 from audit_logs a join event_registration_people p on p.id = a.record_id
                     join event_registrations r on r.id = p.registration_ref where r.registration_id = pg_temp.bid('REG', 'fa1t')),
  'FA1 the test key says the same for each person (self, held, held, already a customer, created, self) and writes no customer or audit row');
-- What staff see.
select pg_temp.as_user('staff');
select pg_temp.put('fa_x', public.event_web_guest_extras(pg_temp.fx('ev'))::text);
create function pg_temp.fa_note(tag text, pos int) returns text language sql as
$$ select coalesce(
     (select g->'referral'->>'note' from jsonb_array_elements(pg_temp.tx('fa_x')::jsonb->'guests') g
       where (g->>'guest_id')::uuid = (pg_temp.fa(tag, pos)).free_guest_id),
     '<none>') $$;
create function pg_temp.fa_hold_note(tag text, pos int) returns text language sql as
$$ select h->>'referral_note' from jsonb_array_elements(pg_temp.tx('fa_x')::jsonb->'holds') h
    where (h->>'person_id')::uuid = (pg_temp.fa(tag, pos)).id $$;
select pg_temp.check(pg_temp.fa_note('fa1', 1) = pg_temp.self_note('name', 'Rhea Linkowner', pg_temp.tx('code_rhea'))
    and pg_temp.fa_hold_note('fa1', 1) = pg_temp.self_note('name', 'Rhea Linkowner', pg_temp.tx('code_rhea'))
    and pg_temp.fa_hold_note('fa1', 2) = pg_temp.shares_note('phone', 'Rhea Linkowner', pg_temp.tx('code_rhea'))
    and pg_temp.fa_note('fa1', 2) = pg_temp.shares_note('phone', 'Rhea Linkowner', pg_temp.tx('code_rhea'))
    and pg_temp.fa_hold_note('fa1', 3) = pg_temp.shares_note('email inbox', 'Rhea Linkowner', pg_temp.tx('code_rhea'))
    and pg_temp.fa_note('fa1', 4) = pg_temp.existing_note(pg_temp.tx('code_rhea'), 'Gail Selfmail')
    and pg_temp.fa_note('fa1', 5) = '<none>'
    and pg_temp.fa_hold_note('fa1', 6) = pg_temp.self_note('name and email inbox', 'Rhea Linkowner', pg_temp.tx('code_rhea')),
  'FA2 the notes on Guests and To match: the affiliate herself; on her phone or inbox, what linking or making a customer does; "Already a customer ... their existing referral (by Gail Selfmail) still stands" (D); none on a plain referral: '
  || coalesce(pg_temp.fa_note('fa1', 4), '?'));
select pg_temp.as_user('owner');
select pg_temp.put('fa1t_tab', public.event_web_settings_get(pg_temp.fx('ev'))::text);
select pg_temp.check((select jsonb_agg(p->'referral_note' order by (p->>'position')::int)
                        from jsonb_array_elements(pg_temp.tx('fa1t_tab')::jsonb->'test'->'registrations') r, jsonb_array_elements(r->'people') p
                       where r->>'registration_id' = pg_temp.bid('REG', 'fa1t'))
    = jsonb_build_array(pg_temp.self_note('name', 'Rhea Linkowner', pg_temp.tx('code_rhea')),
                        pg_temp.shares_note('phone', 'Rhea Linkowner', pg_temp.tx('code_rhea')),
                        pg_temp.shares_note('email inbox', 'Rhea Linkowner', pg_temp.tx('code_rhea')),
                        pg_temp.existing_note(pg_temp.tx('code_rhea'), '?'), null,
                        pg_temp.self_note('name and email inbox', 'Rhea Linkowner', pg_temp.tx('code_rhea'))),
  'FA2 the Website tab''s test registration shows the same notes (on her phone or inbox, what linking or making a customer would do; an existing customer: any referral they have stands)');
-- FA3 staff match the held ones: the mother and the friend made customers (their referral waits for the
-- check), the affiliate linked to her own record (self).
select pg_temp.as_user('staff');
select pg_temp.put('fa3_mona', pg_temp.err(format('select public.event_registration_create_customer(%L, %L)', (pg_temp.fa('fa1', 2)).id, 'Her mother, same phone')));
select pg_temp.put('fa3_frida', pg_temp.err(format('select public.event_registration_create_customer(%L, %L)', (pg_temp.fa('fa1', 3)).id, 'A friend; Rhea typed her own email')));
select pg_temp.put('fa3_rhea', pg_temp.err(format('select public.event_registration_attach(%L, %L, %L)', (pg_temp.fa('fa1', 6)).id, pg_temp.fx('fa_rhea'), 'Rhea herself, a new number')));
select pg_temp.putx('fa_mona', (pg_temp.fa('fa1', 2)).customer_id);
select pg_temp.putx('fa_frida', (pg_temp.fa('fa1', 3)).customer_id);
select pg_temp.check(pg_temp.tx('fa3_mona') = 'ok' and (pg_temp.fa('fa1', 2)).match = 'staff_created'
    and (pg_temp.fa('fa1', 2)).referral_outcome = 'check_waiting'
    and (select (referred_by, referral_source, referral_code_used) is not distinct from (null::uuid, null::text, null::text)
           from customers where id = pg_temp.fx('fa_mona'))
    and ((pg_temp.fa_check(pg_temp.fx('fa_mona'))).status, (pg_temp.fa_check(pg_temp.fx('fa_mona'))).referrer_customer_id,
         (pg_temp.fa_check(pg_temp.fx('fa_mona'))).referral_code, (pg_temp.fa_check(pg_temp.fx('fa_mona'))).phone_shared_with)
        = ('pending', pg_temp.fx('fa_rhea'), pg_temp.tx('code_rhea'), array[pg_temp.fx('fa_rhea')])
    and exists (select 1 from referral_signup_events e where e.new_customer_id = pg_temp.fx('fa_mona') and e.outcome = 'phone_shared'
                  and e.referrer_customer_id = pg_temp.fx('fa_rhea'))
    and exists (select 1 from audit_logs a where a.record_id = pg_temp.fx('fa_mona') and a.action = 'referral_check_waiting'
                  and a.module = 'affiliate' and a.new_data @> jsonb_build_object('referrer_customer_id', pg_temp.fx('fa_rhea'),
                                                                                 'shares', jsonb_build_array('phone')))
    and not exists (select 1 from audit_logs a where a.record_id = pg_temp.fx('fa_mona') and a.action = 'referral_registered')
    and public.event_web_referral_note((pg_temp.fa('fa1', 2)).id) = pg_temp.waiting_note('phone', 'Rhea Linkowner', pg_temp.tx('code_rhea')),
  'FA3 (A) staff make a customer of the mother on Rhea''s phone: no referrer yet, a pending check naming Rhea (Q19), the sign-up counted for the link, audited, the note says it waits: ' || pg_temp.tx('fa3_mona'));
select pg_temp.check(pg_temp.tx('fa3_frida') = 'ok' and (pg_temp.fa('fa1', 3)).referral_outcome = 'check_waiting'
    and (select referred_by from customers where id = pg_temp.fx('fa_frida')) is null
    and ((pg_temp.fa_check(pg_temp.fx('fa_frida'))).status, (pg_temp.fa_check(pg_temp.fx('fa_frida'))).referrer_customer_id,
         (pg_temp.fa_check(pg_temp.fx('fa_frida'))).phone_shared_with)
        = ('pending', pg_temp.fx('fa_rhea'), array[pg_temp.fx('fa_rhea')])
    and public.event_web_referral_note((pg_temp.fa('fa1', 3)).id) = pg_temp.waiting_note('email inbox', 'Rhea Linkowner', pg_temp.tx('code_rhea')),
  'FA3 (A) staff make a customer of the friend on Rhea''s Gmail inbox: the same, a pending check naming Rhea: ' || pg_temp.tx('fa3_frida'));
select pg_temp.check(pg_temp.tx('fa3_rhea') = 'ok' and (pg_temp.fa('fa1', 6)).customer_id = pg_temp.fx('fa_rhea')
    and (pg_temp.fa('fa1', 6)).referral_outcome = 'self' and (pg_temp.fa('fa1', 6)).referral_self_by = array['customer', 'name', 'email']
    and (select referred_by from customers where id = pg_temp.fx('fa_rhea')) = pg_temp.fx('fa_uma')
    and not exists (select 1 from referral_signup_checks k where k.customer_id = pg_temp.fx('fa_rhea'))
    and pg_temp.self_audits((pg_temp.fa('fa1', 6)).id) = 1,
  'FA3 (B) staff link the affiliate (her name, a new phone) to her own record: self, no check, her own referrer kept, the note written once: ' || pg_temp.tx('fa3_rhea'));
-- The mother and the friend visit the centre today (a survey through its own link), while their checks wait.
select pg_temp.as_user('owner');
do $$ declare l uuid; st uuid := (select s.store_id from event_web_settings s where s.event_id = pg_temp.fx('ev')); begin
  insert into survey_links(token, store_id) values ('ht436-fa-' || lower(pg_temp.tx('sfx')), st) returning id into l;
  insert into health_surveys(survey_no, store_id, survey_link_id, customer_id, full_name, phone, source, submitted_at, signed_date)
  select 'HS-HT436-' || x.k || '-' || pg_temp.tx('sfx'), st, l, c.id, c.full_name, c.phone, 'public_form', now(), public.sg_today()
    from (values ('mona', pg_temp.fx('fa_mona')), ('frida', pg_temp.fx('fa_frida'))) x(k, id) join customers c on c.id = x.id;
end $$;
-- FA4 VIP while the checks wait: one payment for the mother, the friend, the new person and Rhea herself.
select pg_temp.put('fa4c', pg_temp.checkout('live', 'fa4', array[pg_temp.tok(pg_temp.tx('fa1')::jsonb, 2), pg_temp.tok(pg_temp.tx('fa1')::jsonb, 3),
                                                                pg_temp.tok(pg_temp.tx('fa1')::jsonb, 5), pg_temp.tok(pg_temp.tx('fa1')::jsonb, 6)])::text);
select pg_temp.put('fa4p', pg_temp.paid('live', 'fa4', array[pg_temp.tok(pg_temp.tx('fa1')::jsonb, 2), pg_temp.tok(pg_temp.tx('fa1')::jsonb, 3),
                                                            pg_temp.tok(pg_temp.tx('fa1')::jsonb, 5), pg_temp.tok(pg_temp.tx('fa1')::jsonb, 6)], 28800)::text);
select pg_temp.putx('fa_inv_mona', pg_temp.fa_inv('fa4', (pg_temp.fa('fa1', 2)).id));
select pg_temp.putx('fa_inv_frida', pg_temp.fa_inv('fa4', (pg_temp.fa('fa1', 3)).id));
select pg_temp.check((pg_temp.tx('fa4p')::jsonb)->>'status' = 'invoiced'
    and (select count(*) from pg_temp.vinvoices('fa4') i where i.status = 'paid') = 4
    and pg_temp.fa_comm(pg_temp.fx('fa_inv_mona')) = '[]'::jsonb
    and pg_temp.fa_comm(pg_temp.fx('fa_inv_frida')) = '[]'::jsonb
    and pg_temp.fa_comm(pg_temp.fa_inv('fa4', (pg_temp.fa('fa1', 5)).id))
        = jsonb_build_array(jsonb_build_array('tier1', pg_temp.fx('fa_rhea'), 10.80), jsonb_build_array('tier2', pg_temp.fx('fa_uma'), 0.54))
    and pg_temp.fa_comm(pg_temp.fa_inv('fa4', (pg_temp.fa('fa1', 6)).id)) = jsonb_build_array(jsonb_build_array('tier1', pg_temp.fx('fa_uma'), 10.80))
    and not exists (select 1 from referral_campaign_friends(pg_temp.fx('fa_campaign')) f
                     where f.friend_customer_id in (pg_temp.fx('fa_mona'), pg_temp.fx('fa_frida'))),
  'FA4 VIP paid while the checks wait: the mother''s and the friend''s VIPs earn nothing yet, the new person''s earns Rhea and her upline as usual, and Rhea''s own VIP earns her upline (C); the two are not in a referral promotion yet, though both visited today: ' || pg_temp.tx('fa4p'));
-- FA5 the checks (425's list): staff cannot decide; an Owner checks the mother as a different person; a
-- Manager checks the friend as the same person.
select pg_temp.as_user('staff');
select pg_temp.put('fa5_staff', pg_temp.err(format('select public.decide_referral_signup_check(%L, %L, %L)',
  (pg_temp.fa_check(pg_temp.fx('fa_mona'))).id, 'different_person', 'Staff try')));
select pg_temp.as_user('owner');
select pg_temp.put('fa5_list', public.referral_signup_checks_pending()::text);
select pg_temp.check(pg_temp.tx('fa5_staff') <> 'ok' and (pg_temp.fa_check(pg_temp.fx('fa_mona'))).status = 'pending'
    and exists (select 1 from jsonb_array_elements(pg_temp.tx('fa5_list')::jsonb) k
                 where (k->>'customer_id')::uuid = pg_temp.fx('fa_mona') and (k->>'referrer_customer_id')::uuid = pg_temp.fx('fa_rhea')
                   and k->'shares_with'->0->>'name' = 'Rhea Linkowner')
    and exists (select 1 from jsonb_array_elements(pg_temp.tx('fa5_list')::jsonb) k
                 where (k->>'customer_id')::uuid = pg_temp.fx('fa_frida') and (k->>'referrer_customer_id')::uuid = pg_temp.fx('fa_rhea')),
  'FA5 both wait on the Affiliates page''s list (referred by Rhea, sharing with Rhea); staff cannot decide: ' || pg_temp.tx('fa5_staff'));
select pg_temp.put('fa5_mona', public.decide_referral_signup_check((pg_temp.fa_check(pg_temp.fx('fa_mona'))).id, 'different_person',
                                                                  'Her mother: asked at the door, a different birthday')::text);
select pg_temp.check((pg_temp.tx('fa5_mona')::jsonb)->>'ok' = 'true'
    and (select (referred_by, referral_source, referral_code_used, referred_at = created_at)
           = (pg_temp.fx('fa_rhea'), 'affiliate_link', pg_temp.tx('code_rhea'), true) from customers where id = pg_temp.fx('fa_mona'))
    and (pg_temp.fa('fa1', 2)).referral_outcome = 'check_confirmed'
    and exists (select 1 from audit_logs a where a.record_id = pg_temp.fx('fa_mona') and a.action = 'referral_registered'
                  and a.module = 'affiliate'
                  and a.new_data @> jsonb_build_object('referred_by', pg_temp.fx('fa_rhea'), 'check_id', (pg_temp.fa_check(pg_temp.fx('fa_mona'))).id,
                                                       'registration_id', pg_temp.bid('REG', 'fa1')))
    and public.event_web_referral_note((pg_temp.fa('fa1', 2)).id)
        = format('Referred by Rhea Linkowner (link %s) once an Owner or Manager checked them as a different person; commission on their VIP comes from then.',
                 pg_temp.tx('code_rhea')),
  'FA5 (A) the Owner checks the mother as a different person: now Rhea''s referral (dated when she was made a customer), audited with the check: ' || pg_temp.tx('fa5_mona'));
select pg_temp.check(pg_temp.fa_comm(pg_temp.fx('fa_inv_mona'))
        = jsonb_build_array(jsonb_build_array('tier1', pg_temp.fx('fa_rhea'), 10.80), jsonb_build_array('tier2', pg_temp.fx('fa_uma'), 0.54))
    and not exists (select 1 from commissions c join invoices i on i.id = c.invoice_id
                     where c.invoice_id = pg_temp.fx('fa_inv_mona')
                       and c.invoice_paid_date is distinct from (i.paid_at at time zone 'Asia/Singapore')::date)
    and exists (select 1 from referral_campaign_friends(pg_temp.fx('fa_campaign')) f
                 where f.friend_customer_id = pg_temp.fx('fa_mona') and f.referrer_customer_id = pg_temp.fx('fa_rhea') and f.counted),
  'FA5 (A) her VIP, paid while the check waited, now earns Rhea''s commission (S$10.80, her upline S$0.54), dated the day it was paid; she now counts for Rhea in the referral promotion (her visit today)');
select pg_temp.put('fa5_again', public.decide_referral_signup_check((pg_temp.fa_check(pg_temp.fx('fa_mona'))).id, 'same_person', 'Again')::text);
select pg_temp.check((pg_temp.tx('fa5_again')::jsonb)->>'already' = 'true'
    and (select count(*) from commissions where invoice_id = pg_temp.fx('fa_inv_mona')) = 2
    and (select referred_by from customers where id = pg_temp.fx('fa_mona')) = pg_temp.fx('fa_rhea'),
  'FA5 a second decision is refused by 425 (already checked): nothing earned twice, the referral stands');
select pg_temp.as_user('manager');
select pg_temp.put('fa5_frida', public.decide_referral_signup_check((pg_temp.fa_check(pg_temp.fx('fa_frida'))).id, 'same_person',
                                                                   'Rhea herself, a nickname and a new number')::text);
select pg_temp.check((pg_temp.tx('fa5_frida')::jsonb)->>'ok' = 'true'
    and (select referred_by from customers where id = pg_temp.fx('fa_frida')) is null
    and (pg_temp.fa('fa1', 3)).referral_outcome = 'check_same_person'
    and pg_temp.fa_comm(pg_temp.fx('fa_inv_frida')) = '[]'::jsonb
    and not exists (select 1 from audit_logs a where a.record_id = pg_temp.fx('fa_frida') and a.action = 'referral_registered')
    and not exists (select 1 from referral_campaign_friends(pg_temp.fx('fa_campaign')) f where f.friend_customer_id = pg_temp.fx('fa_frida'))
    and public.event_web_referral_note((pg_temp.fa('fa1', 3)).id)
        = format('Not referred: an Owner or Manager checked them as the same person as a customer who already had this phone or email (link %s). No commission comes from it.',
                 pg_temp.tx('code_rhea')),
  'FA5 (A) a Manager checks the friend as the same person: never referred, her VIP earns nothing, the note says so: ' || pg_temp.tx('fa5_frida'));
-- FA6 the Guests tab after the checks.
select pg_temp.as_user('staff');
select pg_temp.put('fa_x', public.event_web_guest_extras(pg_temp.fx('ev'))::text);
select pg_temp.check(pg_temp.fa_note('fa1', 2) like 'Referred by Rhea Linkowner (link %'
    and pg_temp.fa_note('fa1', 3) like 'Not referred: an Owner or Manager checked them as the same person%'
    and pg_temp.fa_note('fa1', 4) = pg_temp.existing_note(pg_temp.tx('code_rhea'), 'Gail Selfmail')
    and pg_temp.fa_note('fa1', 6) = pg_temp.self_note('customer', 'Rhea Linkowner', pg_temp.tx('code_rhea'))
    and not exists (select 1 from jsonb_array_elements(pg_temp.tx('fa_x')::jsonb->'holds') h
                     where (h->>'person_id')::uuid in ((pg_temp.fa('fa1', 2)).id, (pg_temp.fa('fa1', 3)).id, (pg_temp.fa('fa1', 6)).id)),
  'FA6 the Guests tab after the checks: the mother referred, the friend not, Gail''s customer as she was, Rhea herself; none left to match');
-- FA7 another relative on Rhea's phone, checked first by a Manager, then buys VIP: it earns at once (the
-- engine, as any referral's purchase), and once only.
select pg_temp.put('fa7', pg_temp.register('live', 'fa7', jsonb_build_array(
  pg_temp.person(1, 'Pia', 'Partner', pg_temp.ph(240), pg_temp.mail('fa7-1'), array[pg_temp.d(8)])), pg_temp.tx('code_rhea'))::text);
select pg_temp.as_user('staff');
select pg_temp.put('fa7_make', pg_temp.err(format('select public.event_registration_create_customer(%L, %L)', (pg_temp.fa('fa7', 1)).id, 'Her partner, same phone')));
select pg_temp.putx('fa_pia', (pg_temp.fa('fa7', 1)).customer_id);
select pg_temp.as_user('manager');
select pg_temp.put('fa7_check', public.decide_referral_signup_check((pg_temp.fa_check(pg_temp.fx('fa_pia'))).id, 'different_person',
                                                                   'Her partner: a different birthday, asked by phone')::text);
select pg_temp.check(pg_temp.tx('fa7_make') = 'ok' and (pg_temp.tx('fa7_check')::jsonb)->>'ok' = 'true'
    and (pg_temp.fa('fa7', 1)).referral_outcome = 'check_confirmed'
    and (select referred_by from customers where id = pg_temp.fx('fa_pia')) = pg_temp.fx('fa_rhea')
    and not exists (select 1 from commissions c where c.buyer_customer_id = pg_temp.fx('fa_pia')),
  'FA7 (A) a Manager checks another relative on Rhea''s phone as a different person before any VIP: referred, nothing earned yet: ' || pg_temp.tx('fa7_make'));
select pg_temp.put('fa7c', pg_temp.checkout('live', 'fa7', array[pg_temp.tok(pg_temp.tx('fa7')::jsonb, 1)])::text);
select pg_temp.put('fa7p', pg_temp.paid('live', 'fa7', array[pg_temp.tok(pg_temp.tx('fa7')::jsonb, 1)], 7200)::text);
select pg_temp.check((pg_temp.tx('fa7p')::jsonb)->>'status' = 'invoiced'
    and pg_temp.fa_comm(pg_temp.fa_inv('fa7', (pg_temp.fa('fa7', 1)).id))
        = jsonb_build_array(jsonb_build_array('tier1', pg_temp.fx('fa_rhea'), 10.80), jsonb_build_array('tier2', pg_temp.fx('fa_uma'), 0.54))
    and (select count(*) from commissions c where c.buyer_customer_id = pg_temp.fx('fa_pia')) = 2,
  'FA7 (A) her VIP bought after the check earns Rhea''s commission at once (S$10.80, her upline S$0.54), once: ' || pg_temp.tx('fa7p'));
-- FA8 someone on Rhea's Gmail inbox made a customer, then found to have an older record of her own and
-- merged into it before the check: the check stays on the merged record (425), deciding it refers nobody,
-- and the note says why.
select pg_temp.as_user('owner');
do $$ declare c uuid; begin
  insert into customers(full_name, phone) values ('Lena Mergeaunt', pg_temp.ph(251)) returning id into c;
  insert into fx values ('fa_lena_old', c);
end $$;
select pg_temp.put('fa8', pg_temp.register('live', 'fa8', jsonb_build_array(
  pg_temp.person(1, 'Lena', 'Mergeaunt', pg_temp.ph(252), 'rhea.link.ht' || lower(pg_temp.tx('sfx')) || '+aunt@gmail.com', array[pg_temp.d(7)])),
  pg_temp.tx('code_rhea'))::text);
select pg_temp.as_user('staff');
select pg_temp.put('fa8_make', pg_temp.err(format('select public.event_registration_create_customer(%L, %L)', (pg_temp.fa('fa8', 1)).id, 'Her aunt, Rhea''s email')));
select pg_temp.putx('fa_lena_new', (pg_temp.fa('fa8', 1)).customer_id);
select pg_temp.putx('fa_lena_check', (pg_temp.fa_check(pg_temp.fx('fa_lena_new'))).id);
select pg_temp.as_user('owner');
select public.merge_customer_records(pg_temp.fx('fa_lena_old'), pg_temp.fx('fa_lena_new'), 'The same person (an older record)', gen_random_uuid());
select pg_temp.put('fa8_check', public.decide_referral_signup_check(pg_temp.fx('fa_lena_check'), 'different_person', 'Checked after the merge')::text);
select pg_temp.check(pg_temp.tx('fa8_make') = 'ok' and (pg_temp.fa('fa8', 1)).hold_reason = 'email_in_use'
    and (pg_temp.fa('fa8', 1)).customer_id = pg_temp.fx('fa_lena_old')
    and (select (k.customer_id, k.status) from referral_signup_checks k where k.id = pg_temp.fx('fa_lena_check'))
        = (pg_temp.fx('fa_lena_new'), 'different_person'::text)
    and (pg_temp.fa('fa8', 1)).referral_outcome = 'check_waiting'
    and (select referred_by from customers where id = pg_temp.fx('fa_lena_old')) is null
    and (select referred_by from customers where id = pg_temp.fx('fa_lena_new')) is null
    and public.event_web_referral_note((pg_temp.fa('fa8', 1)).id)
        = format('Not referred through this link (%s): the customer made for them was merged into another record before the check; '
                 || 'any referral that record has still stands.', pg_temp.tx('code_rhea')),
  'FA8 made a customer, then merged into her older record before the check: deciding it refers nobody, and the note says so: '
  || pg_temp.tx('fa8_make') || ' ' || pg_temp.tx('fa8_check'));
-- FA9 (A) a part refund recorded while the check waits: once an Owner checks her as a different person,
-- her VIP earns on what was kept, exactly as a plain referral's on the same payment with the same refund
-- (S$20 back on S$72: S$7.80, the upline S$0.39), not on the full S$72.
create function pg_temp.fa_live(inv uuid) returns jsonb language sql as
$$ select coalesce(jsonb_agg(jsonb_build_array(t.tier, t.referrer_customer_id, t.status, t.amount) order by t.tier), '[]'::jsonb)
     from (select c.tier::text as tier, c.referrer_customer_id, c.status::text as status, sum(c.commission_amount) as amount
             from commissions c where c.invoice_id = inv and c.status::text <> 'reversed'
            group by 1, 2, 3) t $$;
select pg_temp.as_user('owner');
select pg_temp.put('fa9', pg_temp.register('live', 'fa9', jsonb_build_array(
  pg_temp.person(1, 'Tara', 'Tidewait', pg_temp.ph(260), 'rhea.link.ht' || lower(pg_temp.tx('sfx')) || '+tara@gmail.com', array[pg_temp.d(7)]),
  pg_temp.person(2, 'Carl', 'Control', pg_temp.ph(261), pg_temp.mail('fa9-2'), array[pg_temp.d(7)])), pg_temp.tx('code_rhea'))::text);
select pg_temp.as_user('staff');
select pg_temp.put('fa9_make', pg_temp.err(format('select public.event_registration_create_customer(%L, %L)', (pg_temp.fa('fa9', 1)).id, 'A cousin; Rhea''s email')));
select pg_temp.putx('fa_tara', (pg_temp.fa('fa9', 1)).customer_id);
select pg_temp.put('fa9c', pg_temp.checkout('live', 'fa9', array[pg_temp.tok(pg_temp.tx('fa9')::jsonb, 1), pg_temp.tok(pg_temp.tx('fa9')::jsonb, 2)])::text);
select pg_temp.put('fa9p', pg_temp.paid('live', 'fa9', array[pg_temp.tok(pg_temp.tx('fa9')::jsonb, 1), pg_temp.tok(pg_temp.tx('fa9')::jsonb, 2)], 14400)::text);
select pg_temp.putx('fa_inv_tara', pg_temp.fa_inv('fa9', (pg_temp.fa('fa9', 1)).id));
select pg_temp.putx('fa_inv_carl', pg_temp.fa_inv('fa9', (pg_temp.fa('fa9', 2)).id));
select pg_temp.as_user('owner');
select pg_temp.put('fa9_refund', string_agg(pg_temp.err(format('select public.refund_invoice_recorded(%L, %L::jsonb, %L::jsonb, %L::jsonb, %L, %L)', pg_temp.fx(k),
  jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.ticket(pg_temp.fx(k)), 'amount', 20))::text,
  jsonb_build_array(jsonb_build_object('payment_id', pg_temp.payment(pg_temp.fx(k)), 'amount', 20))::text, '[]',
  'Part refund S$20 (one day missed)', gen_random_uuid())), ',' order by k))
  from unnest(array['fa_inv_tara', 'fa_inv_carl']) k;
select pg_temp.put('fa9_before', pg_temp.fa_live(pg_temp.fx('fa_inv_tara'))::text);
select pg_temp.put('fa9_check', public.decide_referral_signup_check((pg_temp.fa_check(pg_temp.fx('fa_tara'))).id, 'different_person',
                                                                   'A cousin: a different birthday')::text);
select pg_temp.check(pg_temp.tx('fa9_make') = 'ok' and (pg_temp.tx('fa9p')::jsonb)->>'status' = 'invoiced'
    and pg_temp.tx('fa9_refund') = 'ok,ok' and pg_temp.tx('fa9_before') = '[]'
    and (select count(*) from invoices where id in (pg_temp.fx('fa_inv_tara'), pg_temp.fx('fa_inv_carl')) and status::text = 'paid') = 2
    and (pg_temp.tx('fa9_check')::jsonb)->>'ok' = 'true'
    and (pg_temp.fa('fa9', 1)).referral_outcome = 'check_confirmed'
    and (select referred_by from customers where id = pg_temp.fx('fa_tara')) = pg_temp.fx('fa_rhea')
    and pg_temp.fa_live(pg_temp.fx('fa_inv_tara')) = pg_temp.fa_live(pg_temp.fx('fa_inv_carl'))
    and (select jsonb_agg(jsonb_build_array(x->>0, x->>1, (x->>3)::numeric) order by x->>0)
           from jsonb_array_elements(pg_temp.fa_live(pg_temp.fx('fa_inv_tara'))) x)
        = jsonb_build_array(jsonb_build_array('tier1', pg_temp.fx('fa_rhea'), 7.80), jsonb_build_array('tier2', pg_temp.fx('fa_uma'), 0.39)),
  'FA9 (A) a part refund (S$20) recorded while the check waited: checked as a different person, her VIP earns on what was kept, as a plain referral''s with the same refund (S$7.80, her upline S$0.39): '
  || pg_temp.fa_live(pg_temp.fx('fa_inv_tara'))::text || ' vs ' || pg_temp.fa_live(pg_temp.fx('fa_inv_carl'))::text);
-- FA10 (D) an older record of theirs merged INTO the customer made for them (that one kept) before the check:
-- they are an existing customer, so the check refers nobody (an older record with no referral; one Gail
-- referred, whose referral the merge does not carry over: the Owner's to carry), and the note says so,
-- while waiting and after; a record made after theirs and merged into it does not stop the referral.
create function pg_temp.older_merged_note(code text) returns text language sql as
$$ select format('Not referred through this link (%s): an older customer record was merged into the one made for them before the check, '
                 || 'so they are an existing customer; any referral that older record had is the Owner''s to carry over.', code) $$;
select pg_temp.as_user('owner');
do $$ declare o uuid; p uuid; begin
  insert into customers(full_name, phone, created_at) values ('Olga Oldrecord', pg_temp.ph(262), now() - interval '2 years') returning id into o;
  insert into customers(full_name, phone, created_at) values ('Petra Prevref', pg_temp.ph(263), now() - interval '1 year') returning id into p;
  update customers set referred_by = pg_temp.fx('gail') where id = p;
  insert into fx values ('fa_olga_old', o), ('fa_petra_old', p);
end $$;
select pg_temp.put('fa10', pg_temp.register('live', 'fa10', jsonb_build_array(
  pg_temp.person(1, 'Olga', 'Oldrecord', pg_temp.ph(264), 'rhea.link.ht' || lower(pg_temp.tx('sfx')) || '+olga@gmail.com', array[pg_temp.d(7)]),
  pg_temp.person(2, 'Petra', 'Prevref', pg_temp.ph(265), 'rhea.link.ht' || lower(pg_temp.tx('sfx')) || '+petra@gmail.com', array[pg_temp.d(7)]),
  pg_temp.person(3, 'Nora', 'Newdup', pg_temp.ph(266), 'rhea.link.ht' || lower(pg_temp.tx('sfx')) || '+nora@gmail.com', array[pg_temp.d(8)])),
  pg_temp.tx('code_rhea'))::text);
select pg_temp.as_user('staff');
select pg_temp.put('fa10_make', (select string_agg(pg_temp.err(format('select public.event_registration_create_customer(%L, %L)',
                                                                     (pg_temp.fa('fa10', n)).id, 'Not Rhea; Rhea''s email')), ',' order by n)
                                   from generate_series(1, 3) n));
select pg_temp.putx('fa_olga', (pg_temp.fa('fa10', 1)).customer_id);
select pg_temp.putx('fa_petra', (pg_temp.fa('fa10', 2)).customer_id);
select pg_temp.putx('fa_nora', (pg_temp.fa('fa10', 3)).customer_id);
select pg_temp.as_user('owner');
do $$ declare d uuid; begin
  -- A record made for Nora after hers (at the counter, say), later found to be her.
  insert into customers(full_name, phone, created_at) values ('Nora Newdup', pg_temp.ph(267), now() + interval '1 minute') returning id into d;
  insert into fx values ('fa_nora_dup', d);
end $$;
select pg_temp.put('fa10_merge', concat_ws(',',
  pg_temp.err(format('select public.merge_customer_records(%L, %L, %L, %L)', pg_temp.fx('fa_olga'), pg_temp.fx('fa_olga_old'),
                     'The same person; keep the new record', gen_random_uuid())),
  pg_temp.err(format('select public.merge_customer_records(%L, %L, %L, %L)', pg_temp.fx('fa_petra'), pg_temp.fx('fa_petra_old'),
                     'The same person; keep the new record', gen_random_uuid())),
  pg_temp.err(format('select public.merge_customer_records(%L, %L, %L, %L)', pg_temp.fx('fa_nora'), pg_temp.fx('fa_nora_dup'),
                     'Made twice; keep the first', gen_random_uuid()))));
select pg_temp.put('fa10_waiting', concat_ws(' | ', public.event_web_referral_note((pg_temp.fa('fa10', 1)).id),
                                             public.event_web_referral_note((pg_temp.fa('fa10', 3)).id)));
select pg_temp.put('fa10_check', concat_ws(',',
  public.decide_referral_signup_check((pg_temp.fa_check(pg_temp.fx('fa_olga'))).id, 'different_person', 'Not Rhea')->>'ok',
  public.decide_referral_signup_check((pg_temp.fa_check(pg_temp.fx('fa_petra'))).id, 'different_person', 'Not Rhea')->>'ok',
  public.decide_referral_signup_check((pg_temp.fa_check(pg_temp.fx('fa_nora'))).id, 'different_person', 'Not Rhea')->>'ok'));
select pg_temp.check(pg_temp.tx('fa10_make') = 'ok,ok,ok' and pg_temp.tx('fa10_merge') = 'ok,ok,ok' and pg_temp.tx('fa10_check') = 'true,true,true'
    and pg_temp.tx('fa10_waiting') = pg_temp.older_merged_note(pg_temp.tx('code_rhea')) || ' | '
                                     || pg_temp.waiting_note('email inbox', 'Rhea Linkowner', pg_temp.tx('code_rhea'))
    and (pg_temp.fa('fa10', 1)).referral_outcome = 'check_confirmed' and (pg_temp.fa('fa10', 2)).referral_outcome = 'check_confirmed'
    and (select referred_by from customers where id = pg_temp.fx('fa_olga')) is null
    and (select referred_by from customers where id = pg_temp.fx('fa_petra')) is null
    and (select referred_by from customers where id = pg_temp.fx('fa_petra_old')) = pg_temp.fx('gail')
    and not exists (select 1 from audit_logs a where a.record_id in (pg_temp.fx('fa_olga'), pg_temp.fx('fa_petra'))
                      and a.action = 'referral_registered')
    and public.event_web_referral_note((pg_temp.fa('fa10', 1)).id) = pg_temp.older_merged_note(pg_temp.tx('code_rhea'))
    and public.event_web_referral_note((pg_temp.fa('fa10', 2)).id) = pg_temp.older_merged_note(pg_temp.tx('code_rhea')),
  'FA10 (D) an older record (no referral, or Gail''s) merged into the customer made for them before the check: an existing customer, the check refers nobody (Gail''s referral is not carried over by the merge), and the note says so while waiting and after: '
  || pg_temp.tx('fa10_make') || ' ' || pg_temp.tx('fa10_merge') || ' ' || pg_temp.tx('fa10_check'));
select pg_temp.check((pg_temp.fa('fa10', 3)).referral_outcome = 'check_confirmed'
    and (select referred_by from customers where id = pg_temp.fx('fa_nora')) = pg_temp.fx('fa_rhea')
    and public.event_web_referral_note((pg_temp.fa('fa10', 3)).id)
        = format('Referred by Rhea Linkowner (link %s) once an Owner or Manager checked them as a different person; commission on their VIP comes from then.',
                 pg_temp.tx('code_rhea')),
  'FA10 a record made after hers and merged into it does not stop the referral: checked as a different person, she is Rhea''s referral');
-- FA11 checked as a different person, but not referred: the note says why (the affiliate's record deleted
-- while the check waited; their record given another referrer by hand before the check).
select pg_temp.as_user('owner');
do $$ declare g uuid; begin
  insert into customers(full_name, phone) values ('Gwen Goneaff', pg_temp.ph(268)) returning id into g;
  insert into customer_affiliates(customer_id, status, referral_code) values (g, 'active', 'HN' || pg_temp.tx('sfx'));
  insert into fx values ('fa_gwen', g);
  insert into tx values ('code_gwen', 'HN' || pg_temp.tx('sfx'));
end $$;
select pg_temp.put('fa11g', pg_temp.register('live', 'fa11g', jsonb_build_array(
  pg_temp.person(1, 'Hal', 'Housemate', pg_temp.ph(268), pg_temp.mail('fa11-hal'), array[pg_temp.d(7)])), pg_temp.tx('code_gwen'))::text);
select pg_temp.put('fa11r', pg_temp.register('live', 'fa11r', jsonb_build_array(
  pg_temp.person(1, 'Ivy', 'Handref', pg_temp.ph(269), 'rhea.link.ht' || lower(pg_temp.tx('sfx')) || '+ivy@gmail.com', array[pg_temp.d(7)])),
  pg_temp.tx('code_rhea'))::text);
select pg_temp.as_user('staff');
select pg_temp.put('fa11_make', pg_temp.err(format('select public.event_registration_create_customer(%L, %L)', (pg_temp.fa('fa11g', 1)).id, 'Lives with Gwen'))
  || ',' || pg_temp.err(format('select public.event_registration_create_customer(%L, %L)', (pg_temp.fa('fa11r', 1)).id, 'Not Rhea')));
select pg_temp.putx('fa_hal', (pg_temp.fa('fa11g', 1)).customer_id);
select pg_temp.putx('fa_ivy', (pg_temp.fa('fa11r', 1)).customer_id);
select pg_temp.as_user('owner');
select pg_temp.put('fa11_prep', pg_temp.err(format('update customers set deleted_at = now() where id = %L', pg_temp.fx('fa_gwen')))
  || ',' || pg_temp.err(format('select public.reassign_customer_referrer(%L, %L, %L)', pg_temp.fx('fa_ivy'), pg_temp.fx('gail'), 'Gail brought her in')));
select pg_temp.put('fa11_check', concat_ws(',',
  public.decide_referral_signup_check((pg_temp.fa_check(pg_temp.fx('fa_hal'))).id, 'different_person', 'Not Gwen')->>'ok',
  public.decide_referral_signup_check((pg_temp.fa_check(pg_temp.fx('fa_ivy'))).id, 'different_person', 'Not Rhea')->>'ok'));
select pg_temp.check(pg_temp.tx('fa11_make') = 'ok,ok' and pg_temp.tx('fa11_prep') = 'ok,ok' and pg_temp.tx('fa11_check') = 'true,true'
    and (pg_temp.fa('fa11g', 1)).referral_outcome = 'check_confirmed' and (pg_temp.fa('fa11r', 1)).referral_outcome = 'check_confirmed'
    and (select referred_by from customers where id = pg_temp.fx('fa_hal')) is null
    and (select referred_by from customers where id = pg_temp.fx('fa_ivy')) = pg_temp.fx('gail')
    and public.event_web_referral_note((pg_temp.fa('fa11g', 1)).id)
        = format('Checked as a different person, but not referred by Gwen Goneaff (link %s): the affiliate''s customer record is no longer there.',
                 pg_temp.tx('code_gwen'))
    and public.event_web_referral_note((pg_temp.fa('fa11r', 1)).id)
        = format('Checked as a different person, but not referred by Rhea Linkowner (link %s): their customer record has another referrer (Gail Selfmail).',
                 pg_temp.tx('code_rhea')),
  'FA11 checked as a different person but not referred, the note says why: the affiliate''s record deleted while the check waited; another referrer (Gail) given by hand before the check: '
  || pg_temp.tx('fa11_make') || ' ' || pg_temp.tx('fa11_prep') || ' ' || pg_temp.tx('fa11_check') || ' '
  || coalesce(public.event_web_referral_note((pg_temp.fa('fa11g', 1)).id), '-') || ' / ' || coalesce(public.event_web_referral_note((pg_temp.fa('fa11r', 1)).id), '-'));
select pg_temp.as_user('owner');

-- ═════ FQ The owner's answer, 21 Oct 2026: Q19 on another customer's phone waits for the check ═════
-- Hana (F6) and Hugo (FS6), made customers on Rosa's phone through the affiliate's link, have no referrer and a pending
-- check. Their VIP paid while the checks wait earns nothing; staff cannot decide; an Owner checks Hana as a different
-- person: referred (dated when made a customer), and her VIP earns the affiliate's and the upline's commission, once; a
-- second decision changes nothing; a Manager checks Hugo as the same person: never referred, nothing earned. The notes say
-- each.
select pg_temp.as_user('owner');
-- (XR3 reuses the key 'hana' for a counter customer, so their records are read from the registrations.)
select pg_temp.putx('fq_hana', (pg_temp.f1(4)).customer_id);
select pg_temp.putx('fq_hugo', (pg_temp.fs('fs3', 4)).customer_id);
select pg_temp.put('fqc', pg_temp.checkout('live', 'fq', array[pg_temp.tok(pg_temp.tx('f1')::jsonb, 4), pg_temp.tok(pg_temp.tx('fs3')::jsonb, 4)])::text);
select pg_temp.put('fqp', pg_temp.paid('live', 'fq', array[pg_temp.tok(pg_temp.tx('f1')::jsonb, 4), pg_temp.tok(pg_temp.tx('fs3')::jsonb, 4)], 14400)::text);
select pg_temp.putx('fq_inv_hana', pg_temp.fa_inv('fq', (pg_temp.f1(4)).id));
select pg_temp.putx('fq_inv_hugo', pg_temp.fa_inv('fq', (pg_temp.fs('fs3', 4)).id));
select pg_temp.put('fq_list', public.referral_signup_checks_pending()::text);
select pg_temp.check((pg_temp.tx('fqp')::jsonb)->>'status' = 'invoiced'
    and (select count(*) from pg_temp.vinvoices('fq') i where i.status = 'paid') = 2
    and pg_temp.fa_comm(pg_temp.fx('fq_inv_hana')) = '[]'::jsonb and pg_temp.fa_comm(pg_temp.fx('fq_inv_hugo')) = '[]'::jsonb
    and public.event_web_referral_note((pg_temp.f1(4)).id) = pg_temp.other_waiting_note('Aff Testlink', pg_temp.tx('code_ok'))
    and exists (select 1 from jsonb_array_elements(pg_temp.tx('fq_list')::jsonb) k
                 where (k->>'customer_id')::uuid = pg_temp.fx('fq_hana') and (k->>'referrer_customer_id')::uuid = pg_temp.fx('aff')
                   and k->'shares_with'->0->>'name' = 'Rosa Holder'),
  'FQ1 VIP paid while the checks wait (another customer''s phone): Hana''s and Hugo''s VIPs earn nothing yet; Hana waits on the Affiliates page''s list, sharing with Rosa: ' || pg_temp.tx('fqp'));
select pg_temp.as_user('staff');
select pg_temp.put('fq_staff', pg_temp.err(format('select public.decide_referral_signup_check(%L, %L, %L)',
  (pg_temp.fa_check(pg_temp.fx('fq_hana'))).id, 'different_person', 'Staff try')));
select pg_temp.as_user('owner');
select pg_temp.put('fq_hana', public.decide_referral_signup_check((pg_temp.fa_check(pg_temp.fx('fq_hana'))).id, 'different_person',
                                                                 'Rosa''s daughter: a different birthday')::text);
select pg_temp.put('fq_hana_again', public.decide_referral_signup_check((pg_temp.fa_check(pg_temp.fx('fq_hana'))).id, 'same_person', 'Again')::text);
select pg_temp.check(pg_temp.tx('fq_staff') <> 'ok' and (pg_temp.tx('fq_hana')::jsonb)->>'ok' = 'true'
    and (select (referred_by, referral_source, referral_code_used, referred_at = created_at)
           = (pg_temp.fx('aff'), 'affiliate_link', pg_temp.tx('code_ok'), true) from customers where id = pg_temp.fx('fq_hana'))
    and (pg_temp.f1(4)).referral_outcome = 'check_confirmed'
    and pg_temp.fa_comm(pg_temp.fx('fq_inv_hana'))
        = jsonb_build_array(jsonb_build_array('tier1', pg_temp.fx('aff'), 10.80), jsonb_build_array('tier2', pg_temp.fx('upline'), 0.54))
    and (pg_temp.tx('fq_hana_again')::jsonb)->>'already' = 'true'
    and (select count(*) from commissions where invoice_id = pg_temp.fx('fq_inv_hana')) = 2
    and public.event_web_referral_note((pg_temp.f1(4)).id)
        = format('Referred by Aff Testlink (link %s) once an Owner or Manager checked them as a different person; commission on their VIP comes from then.',
                 pg_temp.tx('code_ok')),
  'FQ2 staff cannot decide; the Owner checks Hana as a different person: now the affiliate''s referral, and her VIP paid while it waited earns S$10.80 and the upline S$0.54, once (a second decision changes nothing): ' || pg_temp.tx('fq_staff'));
select pg_temp.as_user('manager');
select pg_temp.put('fq_hugo', public.decide_referral_signup_check((pg_temp.fa_check(pg_temp.fx('fq_hugo'))).id, 'same_person',
                                                                 'Rosa herself, under a nickname')::text);
select pg_temp.check((pg_temp.tx('fq_hugo')::jsonb)->>'ok' = 'true'
    and (select referred_by from customers where id = pg_temp.fx('fq_hugo')) is null
    and (pg_temp.fs('fs3', 4)).referral_outcome = 'check_same_person'
    and pg_temp.fa_comm(pg_temp.fx('fq_inv_hugo')) = '[]'::jsonb
    and not exists (select 1 from audit_logs a where a.record_id = pg_temp.fx('fq_hugo') and a.action = 'referral_registered')
    and public.event_web_referral_note((pg_temp.fs('fs3', 4)).id)
        = format('Not referred: an Owner or Manager checked them as the same person as a customer who already had this phone or email (link %s). No commission comes from it.',
                 pg_temp.tx('code_ok')),
  'FQ3 a Manager checks Hugo as the same person: never referred, his VIP earns nothing, the note says so: ' || pg_temp.tx('fq_hugo'));
select pg_temp.as_user('owner');

-- ═════ PL Planning answers (the owner, 21 Oct 2026, round 7) ═════
-- A dedicated event ev4 (two days, 09:00-19:00, Van, VIP S$72 for both days, Live), so every count is exact.
select pg_temp.as_user('owner');
create function pg_temp.ans(over jsonb default '{}') returns jsonb language sql as
$$ select jsonb_build_object('food', null, 'food_other', null, 'allergy', null, 'allergy_details', null, 'timing', '[]'::jsonb,
            'talks', '[]'::jsonb, 'access', '[]'::jsonb, 'access_other', null, 'heard_from', null, 'heard_from_other', null,
            'question', null) || over $$;
create function pg_temp.part(d date, a text, l text) returns jsonb language sql as
$$ select jsonb_build_object('date', d, 'whole_day', false, 'arrive', a, 'leave', l) $$;
create function pg_temp.whole(d date) returns jsonb language sql as
$$ select jsonb_build_object('date', d, 'whole_day', true, 'arrive', null, 'leave', null) $$;
-- ev null: the main event's code (pg_temp.call falls back to it); ev4's calls pass its code.
create function pg_temp.plan(kind text, people jsonb, ev text default null, req uuid default gen_random_uuid()) returns jsonb
language sql as $$ select pg_temp.call(kind, 'planning_answers', jsonb_build_object('event', ev, 'planning',
  jsonb_build_object('submitted_at', now(), 'people', people)), req) $$;
create function pg_temp.pa(tok text, version int, answers jsonb) returns jsonb language sql as
$$ select jsonb_build_object('upgrade_token', tok, 'version', version, 'answers', answers) $$;
create function pg_temp.prow(gid uuid) returns public.event_planning_answers language sql as
$$ select * from public.event_planning_answers where guest_id = public.event_planning_anchor(gid) $$;
create function pg_temp.plan4(kind text, people jsonb, req uuid default gen_random_uuid()) returns jsonb language sql as
$$ select pg_temp.plan(kind, people, pg_temp.tx('code4'), req) $$;
create function pg_temp.reg4(kind text, tag text, people jsonb) returns jsonb language sql as
$$ select pg_temp.call(kind, 'register', jsonb_build_object('event', pg_temp.tx('code4'), 'registration', jsonb_build_object(
     'registration_id', pg_temp.bid('REG', tag), 'submitted_at', now(), 'referral_code', null, 'people', people))) $$;
create function pg_temp.checkout4(kind text, tag text, tokens text[]) returns jsonb language sql as
$$ select pg_temp.call(kind, 'vip_checkout', jsonb_build_object('event', pg_temp.tx('code4'), 'order', jsonb_build_object(
     'order_id', pg_temp.bid('VIP', tag), 'upgrade_tokens', to_jsonb(tokens),
     'payer', jsonb_build_object('name', 'Payer ' || tag, 'email', pg_temp.mail('payer-' || tag), 'phone', null),
     'livemode', true, 'checkout_opened_at', now() - interval '3 minutes'))) $$;
create function pg_temp.paid4(kind text, tag text, tokens text[], cents int) returns jsonb language sql as
$$ select pg_temp.call(kind, 'vip_paid', jsonb_build_object('event', pg_temp.tx('code4'), 'payment', jsonb_build_object(
     'order_id', pg_temp.bid('VIP', tag), 'provider', 'hitpay', 'payment_request_id', gen_random_uuid(), 'payment_id', gen_random_uuid(),
     'amount_cents', cents, 'currency', 'SGD', 'livemode', true, 'paid_at', now() - interval '1 minute',
     'upgrade_tokens', to_jsonb(tokens),
     'payer', jsonb_build_object('name', 'Payer ' || tag, 'email', pg_temp.mail('payer-' || tag), 'phone', null)))) $$;
create function pg_temp.info4(kind text default 'ev4') returns jsonb language sql as
$$ select pg_temp.call(kind, 'event_info', jsonb_build_object('event', pg_temp.tx('code4'))) $$;
create function pg_temp.person4(kind text, tok text) returns jsonb language sql as
$$ select pg_temp.call(kind, 'person', jsonb_build_object('event', pg_temp.tx('code4'), 'upgrade_token', tok)) $$;
-- One person's result in a planning_answers answer (1 = the first sent).
create function pg_temp.pr(answer text, i int) returns jsonb language sql as $$ select (answer::jsonb)->'people'->(i - 1) $$;
create function pg_temp.plan_audits(plan uuid) returns bigint language sql as
$$ select count(*) from audit_logs a where a.table_name = 'event_planning_answers' and a.record_id = plan $$;
create function pg_temp.reason_of(answer text, i int) returns text language sql as
$$ select pg_temp.pr(answer, i)->>'status' || coalesce(' ' || (pg_temp.pr(answer, i)->>'reason'), '') $$;
do $$ declare ev uuid; r jsonb; begin
  perform pg_temp.as_user('owner');
  ev := public.event_save(jsonb_build_object('name', 'HT436 Planning ' || pg_temp.tx('sfx'), 'daily_start', '09:00', 'daily_end', '19:00',
    'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(11)), jsonb_build_object('day', pg_temp.d(12))),
    'store_ids', jsonb_build_array(pg_temp.fx('van')),
    'options', jsonb_build_array(jsonb_build_object('name', 'VIP', 'days_count', 2, 'price', 72))));
  insert into fx values ('ev4', ev), ('vip4', (select id from public.event_ticket_options where event_id = ev));
  insert into tx values ('code4', 'HT436P-' || pg_temp.tx('sfx'));
  perform public.event_web_settings_save(ev, pg_temp.settings('off', pg_temp.tx('code4')) || jsonb_build_object('vip_option_id', pg_temp.fx('vip4')));
  r := public.event_web_key_create(ev, 'live', 'Planning live');
  insert into tx values ('hash:ev4', encode(extensions.digest(r->>'key', 'sha256'), 'hex'));
  insert into fx values ('key_ev4', (r->>'key_id')::uuid);
  r := public.event_web_key_create(ev, 'test', 'Planning test');
  insert into tx values ('hash:ev4t', encode(extensions.digest(r->>'key', 'sha256'), 'hex'));
  insert into fx values ('key_ev4t', (r->>'key_id')::uuid);
  perform public.event_web_settings_save(ev, pg_temp.settings('live', pg_temp.tx('code4')) || jsonb_build_object('vip_option_id', pg_temp.fx('vip4')));
end $$;

-- PL17 the suggested list, in 436 (the Deno test compares it with the contract's SUGGESTED_TALK_TITLES)
select pg_temp.check(public.event_web_talk_titles(null) = array['Sleep better, stress less', 'Healthy joints, back and muscles',
      'Good circulation for everyday energy', 'Caring for your eyes', 'Ageing well and staying active',
      'Eating well for long-term health', 'Women''s wellness']
    and public.event_web_talk_titles(pg_temp.fx('ev4')) = public.event_web_talk_titles(null),
  'PL17 the suggested talk titles: the seven, in order, until an event saves its own');

-- PL1 the talk titles on the Website tab (Owner, Admin, Manager, as the venue)
select pg_temp.put('pl1_info0', pg_temp.info4()::text);
select pg_temp.put('pl1_ready0', (public.event_web_readiness(pg_temp.fx('ev4'))->'warnings')::text);
select pg_temp.as_user('manager');
select pg_temp.put('pl1_get0', public.event_web_settings_get(pg_temp.fx('ev4'))::text);
select pg_temp.as_user('staff');
select pg_temp.put('pl1_staff', pg_temp.err(format('select public.event_web_set_talks(%L, %L)', pg_temp.fx('ev4'), '["A talk"]')));
select pg_temp.put('pl1_staff_code', pg_temp.errcode(format('select public.event_web_set_talks(%L, %L)', pg_temp.fx('ev4'), '["A talk"]')));
select pg_temp.put('pl1_staff_get', pg_temp.errcode(format('select public.event_web_settings_get(%L)', pg_temp.fx('ev4'))));
select pg_temp.as_user('manager2');
select pg_temp.put('pl1_mgr2', pg_temp.err(format('select public.event_web_set_talks(%L, %L)', pg_temp.fx('ev4'), '["A talk"]')));
select pg_temp.as_user('manager');
select pg_temp.put('pl1_long', pg_temp.err(format('select public.event_web_set_talks(%L, %L)', pg_temp.fx('ev4'), jsonb_build_array(repeat('x', 121)))));
select pg_temp.put('pl1_21', pg_temp.err(format('select public.event_web_set_talks(%L, %L)', pg_temp.fx('ev4'),
  (select jsonb_agg('Talk ' || n) from generate_series(1, 21) n))));
select pg_temp.put('pl1_dup', pg_temp.err(format('select public.event_web_set_talks(%L, %L)', pg_temp.fx('ev4'), '["Sleep well", "SLEEP  WELL"]')));
select pg_temp.put('pl1_set', public.event_web_set_talks(pg_temp.fx('ev4'),
  '["  Sleep   better, stress less ", "Caring for your eyes", "", "Healthy joints, back and muscles", "Ageing well and staying active"]')::text);
select pg_temp.put('pl1_info1', pg_temp.info4()::text);
select pg_temp.put('pl1_ready1', (public.event_web_readiness(pg_temp.fx('ev4'))->'warnings')::text);
select pg_temp.put('pl1_get1', public.event_web_settings_get(pg_temp.fx('ev4'))::text);
select pg_temp.as_user('owner');
select pg_temp.put('pl1_resave', pg_temp.err(format('select public.event_web_settings_save(%L, %L)', pg_temp.fx('ev4'),
  pg_temp.settings('live', pg_temp.tx('code4')) || jsonb_build_object('vip_option_id', pg_temp.fx('vip4')))));
select pg_temp.put('pl1_kept', (select talk_titles::text from event_web_settings where event_id = pg_temp.fx('ev4')));
select pg_temp.as_user('admin');
select pg_temp.put('pl1_none', public.event_web_set_talks(pg_temp.fx('ev4'), '[]')::text);
select pg_temp.put('pl1_info2', pg_temp.info4()::text);
select pg_temp.put('pl1_back', public.event_web_set_talks(pg_temp.fx('ev4'), null)::text);
select pg_temp.put('pl1_info3', pg_temp.info4()::text);
select pg_temp.as_user('owner');
create temp table pl1_set_list as select array['Sleep better, stress less', 'Caring for your eyes', 'Healthy joints, back and muscles',
  'Ageing well and staying active'] as titles;
select pg_temp.check((pg_temp.tx('pl1_info0')::jsonb)->'event' @> '{"talk_titles": null, "planning_open": true}'::jsonb
    and (pg_temp.tx('pl1_ready0')::jsonb) ? 'The talk titles are the suggested list: set the real ones under Talk titles once the speakers'' titles are known.'
    and (pg_temp.tx('pl1_get0')::jsonb)->'talks' = jsonb_build_object('titles', to_jsonb(public.event_web_talk_titles(null)),
          'saved', false, 'suggested', to_jsonb(public.event_web_talk_titles(null)))
    and (pg_temp.tx('pl1_get0')::jsonb)->>'can_set_talks' = 'true'
    and pg_temp.tx('pl1_staff') = 'Your role cannot do this.' and pg_temp.tx('pl1_staff_code') = '42501'
    and pg_temp.tx('pl1_staff_get') = '42501'
    and pg_temp.tx('pl1_mgr2') = 'You do not have access to this event',
  'PL1 before any titles: event_info''s talk_titles null (the suggested list), the readiness list says so, the tab shows the suggested list (can_set_talks for a Manager); staff cannot set them (nor read the tab), a Manager of another store neither: '
  || pg_temp.tx('pl1_staff') || ' / ' || pg_temp.tx('pl1_mgr2'));
select pg_temp.check(pg_temp.tx('pl1_long') = 'A talk title is at most 120 characters: ' || repeat('x', 40) || '…'
    and pg_temp.tx('pl1_21') = 'At most 20 talk titles'
    and pg_temp.tx('pl1_dup') = 'Each talk title only once: SLEEP WELL',
  'PL1 a title of 121 characters, 21 titles, the same title twice in other case and spacing: refused, saying which: '
  || pg_temp.tx('pl1_long') || ' / ' || pg_temp.tx('pl1_21') || ' / ' || pg_temp.tx('pl1_dup'));
select pg_temp.check((pg_temp.tx('pl1_set')::jsonb) = jsonb_build_object('ok', true, 'talk_titles', to_jsonb((select titles from pl1_set_list)), 'saved', true)
    and (pg_temp.tx('pl1_info1')::jsonb)->'event'->'talk_titles' = to_jsonb((select titles from pl1_set_list))
    and not ((pg_temp.tx('pl1_ready1')::jsonb) ? 'The talk titles are the suggested list: set the real ones under Talk titles once the speakers'' titles are known.')
    and (pg_temp.tx('pl1_get1')::jsonb)->'talks' @> jsonb_build_object('titles', to_jsonb((select titles from pl1_set_list)), 'saved', true)
    and exists (select 1 from audit_logs a where a.table_name = 'event_web_settings' and a.record_id = pg_temp.fx('ev4')
                  and a.action = 'event_web_talks_set' and a.changed_by = pg_temp.fx('manager')
                  and a.old_data = '{"talk_titles": null}'::jsonb
                  and a.new_data = jsonb_build_object('talk_titles', to_jsonb((select titles from pl1_set_list)))),
  'PL1 a Manager sets the titles (trimmed, inner spaces made one, blanks dropped, in order): event_info returns them, the readiness warning goes, audited (old and new): '
  || pg_temp.tx('pl1_set'));
select pg_temp.check(pg_temp.tx('pl1_resave') = 'ok'
    and pg_temp.tx('pl1_kept')::text[] = (select titles from pl1_set_list),
  'PL1 the Owner saving the website settings afterwards keeps the titles (as the venue): ' || pg_temp.tx('pl1_resave'));
select pg_temp.check((pg_temp.tx('pl1_none')::jsonb) = '{"ok": true, "talk_titles": [], "saved": true}'::jsonb
    and (pg_temp.tx('pl1_info2')::jsonb)->'event'->'talk_titles' = '[]'::jsonb
    and (pg_temp.tx('pl1_back')::jsonb) = jsonb_build_object('ok', true, 'talk_titles', to_jsonb(public.event_web_talk_titles(null)), 'saved', false)
    and (pg_temp.tx('pl1_info3')::jsonb)->'event'->'talk_titles' = 'null'::jsonb,
  'PL1 an Admin sets none ([]: the website does not ask about talks), then back to the suggested list (null)');

-- PL2 two people register on ev4; Pia (Day 1) saves her answers by her own link token
select pg_temp.put('pl_r', pg_temp.reg4('ev4', 'pl', jsonb_build_array(
  pg_temp.person(1, 'Pia', 'Planner', pg_temp.ph(300), pg_temp.mail('pl-pia'), array[pg_temp.d(11)]),
  pg_temp.person(2, 'Quin', 'Planner', pg_temp.ph(301), pg_temp.mail('pl-quin'), array[pg_temp.d(12)]),
  pg_temp.person(3, 'Sol', 'Planner', pg_temp.ph(302), pg_temp.mail('pl-sol'), array[pg_temp.d(11), pg_temp.d(12)])))::text);
select pg_temp.putx(k, pg_temp.pid(pg_temp.tx('pl_r')::jsonb, n)) from (values ('pia', 1), ('quin', 2), ('sol', 3)) x(k, n);
select pg_temp.put('tok:' || k, pg_temp.tok(pg_temp.tx('pl_r')::jsonb, n)) from (values ('pia', 1), ('quin', 2), ('sol', 3)) x(k, n);
create function pg_temp.pia_answers() returns jsonb language sql as
$$ select pg_temp.ans(jsonb_build_object('food', 'vegetarian', 'timing', jsonb_build_array(pg_temp.part(pg_temp.d(11), '14:00', '19:00')),
     'talks', jsonb_build_array('caring for your eyes', 'Sleep better, stress less', 'Caring For Your Eyes'))) $$;
select pg_temp.put('pl2_req', gen_random_uuid()::text);
select pg_temp.put('pl2', pg_temp.plan4('ev4', jsonb_build_array(pg_temp.pa(pg_temp.tx('tok:pia'), 0, pg_temp.pia_answers())),
  pg_temp.tx('pl2_req')::uuid)::text);
select pg_temp.putx('plan_pia', (pg_temp.prow((pg_temp.pp(pg_temp.fx('pia'))).free_guest_id)).id);
select pg_temp.check((pg_temp.tx('pl2')::jsonb) - 'people' = '{"ok": true, "test": false, "status": "ok"}'::jsonb
    and pg_temp.pr(pg_temp.tx('pl2'), 1) - 'planning' = jsonb_build_object('person_id', pg_temp.fx('pia'), 'status', 'saved', 'reason', null)
    and (pg_temp.pr(pg_temp.tx('pl2'), 1)->'planning') - 'updated_at' = jsonb_build_object('version', 1, 'updated_by', 'guest',
          'answers', pg_temp.ans(jsonb_build_object('food', 'vegetarian',
            'timing', jsonb_build_array(pg_temp.part(pg_temp.d(11), '14:00', '19:00')),
            'talks', jsonb_build_array('Sleep better, stress less', 'Caring for your eyes'))))
    and (select (guest_id, person_id, event_id, version, answered_by, staff_id) is not distinct from ((pg_temp.pp(pg_temp.fx('pia'))).free_guest_id, pg_temp.fx('pia'),
                 pg_temp.fx('ev4'), 1, 'guest'::text, null::uuid)
           from event_planning_answers where id = pg_temp.fx('plan_pia'))
    and exists (select 1 from audit_logs a where a.record_id = pg_temp.fx('plan_pia') and a.action = 'event_planning_added'
                  and a.old_data is null and a.new_data @> '{"source": "website", "version": 1, "food": "vegetarian"}'::jsonb
                  and a.reason = 'Answered on the website' and a.module = 'events')
    and not pg_temp.says_who(pg_temp.tx('pl2')::jsonb)
    and pg_temp.tx('pl2') !~ 'plan_id|staff_id',
  'PL2 Pia''s answers by her own link token: saved, version 1, by the guest; kept on her first (free) record, with her person; talks matched in any case, spelled as the list spells them, once each, in its order; audited as the website; the answer says nothing about who she is: '
  || pg_temp.tx('pl2'));

-- PL3 replays, the same answers again, a new version, a stale version
select pg_temp.put('pl3_again', pg_temp.plan4('ev4', jsonb_build_array(pg_temp.pa(pg_temp.tx('tok:pia'), 0, pg_temp.pia_answers())),
  pg_temp.tx('pl2_req')::uuid)::text);
select pg_temp.put('pl3_same', pg_temp.plan4('ev4', jsonb_build_array(pg_temp.pa(pg_temp.tx('tok:pia'), 0, pg_temp.pia_answers())))::text);
select pg_temp.put('pl3_v2', pg_temp.plan4('ev4', jsonb_build_array(pg_temp.pa(pg_temp.tx('tok:pia'), 1,
  pg_temp.pia_answers() || '{"allergy": "no"}'::jsonb)))::text);
select pg_temp.put('pl3_stale', pg_temp.plan4('ev4', jsonb_build_array(pg_temp.pa(pg_temp.tx('tok:pia'), 1,
  pg_temp.pia_answers() || '{"allergy": "yes", "allergy_details": "Shellfish"}'::jsonb)))::text);
select pg_temp.check(pg_temp.tx('pl3_again')::jsonb = pg_temp.tx('pl2')::jsonb
    and pg_temp.reason_of(pg_temp.tx('pl3_same'), 1) = 'saved' and pg_temp.pr(pg_temp.tx('pl3_same'), 1)->'planning'->>'version' = '1'
    and pg_temp.reason_of(pg_temp.tx('pl3_v2'), 1) = 'saved' and pg_temp.pr(pg_temp.tx('pl3_v2'), 1)->'planning'->>'version' = '2'
    and pg_temp.reason_of(pg_temp.tx('pl3_stale'), 1) = 'refused changed_meanwhile'
    and pg_temp.pr(pg_temp.tx('pl3_stale'), 1)->'planning' = pg_temp.pr(pg_temp.tx('pl3_v2'), 1)->'planning'
    and (select (version, allergy, allergy_details) is not distinct from (2, 'no'::text, null::text) from event_planning_answers where id = pg_temp.fx('plan_pia'))
    and pg_temp.plan_audits(pg_temp.fx('plan_pia')) = 2
    and (select count(*) from event_web_requests where key_id = pg_temp.fx('key_ev4') and type = 'planning_answers' and is_write) = 4,
  'PL3 the same request id again: the first answer; a new request id with the same answers (version 0): saved, version 1, nothing written; version 1 with other answers: version 2; version 1 again: refused changed_meanwhile with version 2''s answers, nothing written; each request logged: '
  || pg_temp.tx('pl3_stale'));

-- PL4 people on their own, in the order sent
select pg_temp.put('pl4', pg_temp.plan4('ev4', jsonb_build_array(
  pg_temp.pa(pg_temp.tx('tok:pia'), 2, pg_temp.pia_answers() || '{"allergy": "no"}'::jsonb),
  pg_temp.pa(pg_temp.tx('tok:quin'), 0, pg_temp.ans(jsonb_build_object('timing', jsonb_build_array(pg_temp.whole(pg_temp.d(11)))))),
  pg_temp.pa('vip_aaaaaaaaaaaaaaaaaaaaaaaaaa', 0, pg_temp.ans())))::text);
select pg_temp.check(pg_temp.reason_of(pg_temp.tx('pl4'), 1) = 'saved'
    and pg_temp.pr(pg_temp.tx('pl4'), 2) = jsonb_build_object('person_id', pg_temp.fx('quin'), 'status', 'refused', 'reason', 'day_not_chosen', 'planning', null)
    and pg_temp.pr(pg_temp.tx('pl4'), 3) = '{"person_id": null, "status": "refused", "reason": "person_not_found", "planning": null}'::jsonb
    and jsonb_array_length((pg_temp.tx('pl4')::jsonb)->'people') = 3
    and pg_temp.prow((pg_temp.pp(pg_temp.fx('quin'))).free_guest_id) is null,
  'PL4 one call for three: Pia saved; Quin refused day_not_chosen (Day 1 is not his day), nothing kept for him; an unknown token person_not_found with no id: '
  || pg_temp.tx('pl4'));

-- PL5 the times: half hours within the event's hours, leaving after arriving; a whole day from start to end
select pg_temp.put('pl5_' || k, pg_temp.reason_of(pg_temp.plan4('ev4', jsonb_build_array(pg_temp.pa(pg_temp.tx('tok:quin'), 0,
  pg_temp.ans(jsonb_build_object('timing', jsonb_build_array(pg_temp.part(pg_temp.d(12), a, l)))))))::text, 1))
  from (values ('early', '08:30', '19:00'), ('late', '18:45', '19:00'), ('after', '14:00', '19:30'), ('same', '14:00', '14:00'),
               ('quarter', '14:15', '19:00'), ('last', '18:30', '19:00')) x(k, a, l);
select pg_temp.put('pl5_full', pg_temp.plan4('ev4', jsonb_build_array(pg_temp.pa(pg_temp.tx('tok:quin'), 1,
  pg_temp.ans(jsonb_build_object('timing', jsonb_build_array(pg_temp.part(pg_temp.d(12), '09:00', '19:00')))))))::text);
select pg_temp.check(pg_temp.tx('pl5_early') = 'refused outside_hours' and pg_temp.tx('pl5_late') = 'refused outside_hours'
    and pg_temp.tx('pl5_after') = 'refused outside_hours' and pg_temp.tx('pl5_same') = 'refused outside_hours'
    and pg_temp.tx('pl5_quarter') = 'refused outside_hours' and pg_temp.tx('pl5_last') = 'saved'
    and pg_temp.reason_of(pg_temp.tx('pl5_full'), 1) = 'saved'
    and pg_temp.pr(pg_temp.tx('pl5_full'), 1)->'planning'->'answers'->'timing' = jsonb_build_array(pg_temp.whole(pg_temp.d(12)))
    and pg_temp.pr(pg_temp.tx('pl5_full'), 1)->'planning'->>'version' = '2',
  'PL5 arriving 8:30 am or 6:45 pm, leaving 7:30 pm, leaving when arriving, arriving 2:15 pm: outside_hours; 6:30 to 7:00 pm saved; 9:00 am to 7:00 pm is kept as the whole day: '
  || pg_temp.tx('pl5_early') || ' ' || pg_temp.tx('pl5_late') || ' ' || pg_temp.tx('pl5_after') || ' ' || pg_temp.tx('pl5_same') || ' ' || pg_temp.tx('pl5_quarter'));
update events set daily_start = null where id = pg_temp.fx('ev4');
select pg_temp.put('pl5_nohours', pg_temp.plan4('ev4', jsonb_build_array(pg_temp.pa(pg_temp.tx('tok:quin'), 2,
  pg_temp.ans(jsonb_build_object('timing', jsonb_build_array(pg_temp.part(pg_temp.d(12), '10:00', '19:00')))))))::text);
select pg_temp.put('pl5_nohours_whole', pg_temp.plan4('ev4', jsonb_build_array(pg_temp.pa(pg_temp.tx('tok:quin'), 2,
  pg_temp.ans(jsonb_build_object('food', 'halal', 'timing', jsonb_build_array(pg_temp.whole(pg_temp.d(12))))))))::text);
select pg_temp.as_user('staff');
select pg_temp.put('pl5_nohours_staff', pg_temp.err(format('select public.event_planning_save(%L, %L, 3, null)',
  (pg_temp.pp(pg_temp.fx('quin'))).free_guest_id, pg_temp.ans(jsonb_build_object('timing', jsonb_build_array(pg_temp.part(pg_temp.d(12), '10:00', '19:00')))))));
select pg_temp.as_user('owner');
update events set daily_start = '10:15' where id = pg_temp.fx('ev4');
-- Pia's kept 2:00 pm (not a half hour from 10:15 am) passes again as it is; a new time must follow the hours now.
select pg_temp.put('pl5_kept', pg_temp.plan4('ev4', jsonb_build_array(pg_temp.pa(pg_temp.tx('tok:pia'), 2,
  pg_temp.pia_answers() || '{"allergy": "no", "heard_from": "tiktok"}'::jsonb)))::text);
select pg_temp.put('pl5_new', pg_temp.reason_of(pg_temp.plan4('ev4', jsonb_build_array(pg_temp.pa(pg_temp.tx('tok:sol'), 0,
  pg_temp.ans(jsonb_build_object('timing', jsonb_build_array(pg_temp.part(pg_temp.d(11), '14:00', '19:00')))))))::text, 1));
select pg_temp.put('pl5_new2', pg_temp.reason_of(pg_temp.plan4('ev4', jsonb_build_array(pg_temp.pa(pg_temp.tx('tok:sol'), 0,
  pg_temp.ans(jsonb_build_object('timing', jsonb_build_array(pg_temp.part(pg_temp.d(11), '09:30', '19:00')))))))::text, 1));
update events set daily_start = '09:00' where id = pg_temp.fx('ev4');
select pg_temp.check(pg_temp.reason_of(pg_temp.tx('pl5_nohours'), 1) = 'refused outside_hours'
    and pg_temp.reason_of(pg_temp.tx('pl5_nohours_whole'), 1) = 'saved'
    and pg_temp.tx('pl5_nohours_staff') = 'Part-day times cannot be kept yet: the event has no daily hours (Edit event).'
    and pg_temp.reason_of(pg_temp.tx('pl5_kept'), 1) = 'saved'
    and pg_temp.pr(pg_temp.tx('pl5_kept'), 1)->'planning'->'answers'->'timing' = jsonb_build_array(pg_temp.part(pg_temp.d(11), '14:00', '19:00'))
    and pg_temp.tx('pl5_new') = 'refused outside_hours' and pg_temp.tx('pl5_new2') = 'refused outside_hours',
  'PL5 without daily hours a part day is outside_hours (staff are told why) and a whole day saves; the hours moved to 10:15 am: Pia''s kept 2:00 pm passes again as it is, a new 2:00 pm or 9:30 am does not: '
  || pg_temp.tx('pl5_nohours_staff'));

-- PL6 the talks: the event's titles now (any case), or one already kept for that person
select pg_temp.put('pl6_bad', pg_temp.plan4('ev4', jsonb_build_array(pg_temp.pa(pg_temp.tx('tok:sol'), 0,
  pg_temp.ans('{"talks": ["Detox secrets"]}'::jsonb))))::text);
select pg_temp.as_user('manager');
select public.event_web_set_talks(pg_temp.fx('ev4'), to_jsonb(array['Sleep better, stress less', 'Healthy joints, back and muscles',
  'Good circulation for everyday energy', 'Caring for your eyes and vision', 'Ageing well and staying active',
  'Eating well for long-term health', 'Women''s wellness']));
select pg_temp.as_user('owner');
select pg_temp.put('pl6_kept', pg_temp.plan4('ev4', jsonb_build_array(pg_temp.pa(pg_temp.tx('tok:pia'), 3,
  pg_temp.pia_answers() || '{"allergy": "no", "heard_from": "tiktok", "question": "How long should I sleep?"}'::jsonb)))::text);
select pg_temp.put('pl6_other', pg_temp.plan4('ev4', jsonb_build_array(pg_temp.pa(pg_temp.tx('tok:sol'), 0,
  pg_temp.ans('{"talks": ["Caring for your eyes"]}'::jsonb))))::text);
select pg_temp.check(pg_temp.pr(pg_temp.tx('pl6_bad'), 1) = jsonb_build_object('person_id', pg_temp.fx('sol'), 'status', 'refused',
          'reason', 'talk_not_offered', 'planning', null)
    and pg_temp.reason_of(pg_temp.tx('pl6_kept'), 1) = 'saved'
    and pg_temp.pr(pg_temp.tx('pl6_kept'), 1)->'planning'->'answers'->'talks' = '["Sleep better, stress less", "Caring for your eyes"]'::jsonb
    and pg_temp.reason_of(pg_temp.tx('pl6_other'), 1) = 'refused talk_not_offered',
  'PL6 a talk that is not offered: talk_not_offered; a title renamed after Pia chose it: her old title passes again as kept, someone else sending it is refused: '
  || pg_temp.tx('pl6_kept'));

-- PL7 one form for every answer (the staff path and a direct call alike)
select pg_temp.put('pl7_web', pg_temp.plan4('ev4', jsonb_build_array(pg_temp.pa(pg_temp.tx('tok:sol'), 0, pg_temp.ans(jsonb_build_object(
  'food', 'vegan', 'food_other', 'No pork', 'allergy', 'no', 'allergy_details', 'Peanuts', 'heard_from', 'tiktok', 'heard_from_other', 'Radio',
  'access', '["front_seat", "wheelchair", "front_seat"]'::jsonb, 'access_other', '  Needs   a ramp ',
  'question', E'  Line one\r\nLine two\r\n', 'timing', jsonb_build_array(pg_temp.whole(pg_temp.d(12)), pg_temp.part(pg_temp.d(11), '09:00', '12:00')))))))::text);
select pg_temp.as_user('staff');
select pg_temp.put('pl7_staff', public.event_planning_save((pg_temp.pp(pg_temp.fx('quin'))).free_guest_id, jsonb_build_object(
  'food', 'other', 'food_other', '  No   pork ', 'allergy', 'yes', 'heard_from', 'other', 'heard_from_other', ' Community   notice ',
  'question', E'Line one\rLine two'), 3, ' Told by phone ')::text);
-- (the staff path drops a text sent without its choice too: on the main event's walk-in guest, so ev4's counts stay as they are)
select pg_temp.put('pl7_staff_drop', public.event_planning_save((select id from event_guests where event_id = pg_temp.fx('ev') and name = 'Walk In Guest'),
  jsonb_build_object('food', 'vegan', 'food_other', 'No pork', 'allergy', 'no', 'allergy_details', 'Peanuts', 'heard_from', 'tiktok',
                     'heard_from_other', 'Radio'), 0, null)::text);
select pg_temp.as_user('owner');
select pg_temp.put('pl7_bad', pg_temp.errcode(format('select pg_temp.plan4(%L, %L)', 'ev4', jsonb_build_array(pg_temp.pa(pg_temp.tx('tok:sol'), 1,
  pg_temp.ans('{"food": "pescatarian"}'::jsonb))))));
select pg_temp.put('pl7_ver_' || k, pg_temp.errcode(format('select pg_temp.plan4(%L, %L)', 'ev4', jsonb_build_array(
  case when k = 'missing' then pg_temp.pa(pg_temp.tx('tok:sol'), 1, pg_temp.ans('{"food": "halal"}'::jsonb)) - 'version'
       else pg_temp.pa(pg_temp.tx('tok:sol'), 1, pg_temp.ans('{"food": "halal"}'::jsonb)) || jsonb_build_object('version', v) end))))
  from (values ('missing', null::jsonb), ('null', 'null'::jsonb), ('minus', '-1'::jsonb), ('half', '1.5'::jsonb), ('text', '"1"'::jsonb)) x(k, v);
select pg_temp.check(pg_temp.reason_of(pg_temp.tx('pl7_web'), 1) = 'saved'
    and pg_temp.pr(pg_temp.tx('pl7_web'), 1)->'planning'->'answers' = pg_temp.ans(jsonb_build_object('food', 'vegan', 'allergy', 'no',
          'heard_from', 'tiktok', 'access', '["wheelchair", "front_seat"]'::jsonb, 'access_other', 'Needs a ramp',
          'question', E'Line one\nLine two',
          'timing', jsonb_build_array(pg_temp.part(pg_temp.d(11), '09:00', '12:00'), pg_temp.whole(pg_temp.d(12))))),
  'PL7 the website path: a text sent without its choice is dropped (food Other, allergy details, heard Other), needs once each in the list''s order, texts trimmed (inner spaces one), the question''s line breaks kept as \n, days by date: '
  || (pg_temp.pr(pg_temp.tx('pl7_web'), 1)->'planning'->'answers')::text);
select pg_temp.check((pg_temp.tx('pl7_staff')::jsonb)->'answers' = pg_temp.ans(jsonb_build_object('food', 'other', 'food_other', 'No pork',
          'allergy', 'yes', 'heard_from', 'other', 'heard_from_other', 'Community notice', 'question', E'Line one\nLine two'))
    and (pg_temp.tx('pl7_staff')::jsonb) @> jsonb_build_object('ok', true, 'guest_id', (pg_temp.pp(pg_temp.fx('quin'))).free_guest_id,
          'changed', true, 'updated_by', 'staff', 'version', 4)
    and not ((pg_temp.tx('pl7_staff')::jsonb) ? 'staff_id')
    and (pg_temp.tx('pl7_staff_drop')::jsonb)->'answers' = pg_temp.ans('{"food": "vegan", "allergy": "no", "heard_from": "tiktok"}'::jsonb),
  'PL7 the staff path: keys left out are not answered; "  No   pork " with Other is "No pork"; allergy Yes without details kept; a lone \r is a line break; a text sent without its choice is dropped (no error): '
  || pg_temp.tx('pl7_staff'));
select pg_temp.check(pg_temp.tx('pl7_bad') = '22023' and pg_temp.tx('pl7_ver_missing') = '22023' and pg_temp.tx('pl7_ver_null') = '22023'
    and pg_temp.tx('pl7_ver_minus') = '22023' and pg_temp.tx('pl7_ver_half') = '22023' and pg_temp.tx('pl7_ver_text') = '22023'
    and (select version from event_planning_answers a where a.person_id = pg_temp.fx('sol')) = 1,
  'PL7 a direct call with a choice that is not the contract''s, or a version missing, null, -1, 1.5 or "1": class 22 (22023), nothing written');

-- PL8 Pia buys VIP (with Ravi on the same payment): her answers follow her to her VIP record, which covers both days
select pg_temp.put('pl8_r', pg_temp.reg4('ev4', 'pl8', jsonb_build_array(
  pg_temp.person(1, 'Ravi', 'Planner', pg_temp.ph(303), pg_temp.mail('pl-ravi'), array[pg_temp.d(11)])))::text);
select pg_temp.putx('ravi', pg_temp.pid(pg_temp.tx('pl8_r')::jsonb, 1));
select pg_temp.put('tok:ravi', pg_temp.tok(pg_temp.tx('pl8_r')::jsonb, 1));
select pg_temp.put('pl8_d12_before', pg_temp.reason_of(pg_temp.plan4('ev4', jsonb_build_array(pg_temp.pa(pg_temp.tx('tok:ravi'), 0,
  pg_temp.ans(jsonb_build_object('timing', jsonb_build_array(pg_temp.whole(pg_temp.d(12))))))))::text, 1));
select pg_temp.checkout4('ev4', 'pl8', array[pg_temp.tx('tok:pia'), pg_temp.tx('tok:ravi')]);
select pg_temp.put('pl8_paid', pg_temp.paid4('ev4', 'pl8', array[pg_temp.tx('tok:pia'), pg_temp.tx('tok:ravi')], 14400)::text);
select pg_temp.as_user('staff');
select pg_temp.put('pl8_list', public.event_planning_list(pg_temp.fx('ev4'))::text);
select pg_temp.as_user('owner');
select pg_temp.put('pl8_d12_after', pg_temp.reason_of(pg_temp.plan4('ev4', jsonb_build_array(pg_temp.pa(pg_temp.tx('tok:ravi'), 0,
  pg_temp.ans(jsonb_build_object('food', 'no_beef', 'timing', jsonb_build_array(pg_temp.whole(pg_temp.d(12))),
    'access', '["walking_help"]'::jsonb)))))::text, 1));
create function pg_temp.list_row(list text, gid uuid) returns jsonb language sql as
$$ select x from jsonb_array_elements((list::jsonb)->'guests') x where (x->>'guest_id')::uuid = gid $$;
select pg_temp.check((pg_temp.tx('pl8_paid')::jsonb)->>'status' = 'invoiced'
    and public.event_planning_anchor((pg_temp.pp(pg_temp.fx('pia'))).vip_guest_id) = (pg_temp.pp(pg_temp.fx('pia'))).free_guest_id
    and pg_temp.list_row(pg_temp.tx('pl8_list'), (pg_temp.pp(pg_temp.fx('pia'))).vip_guest_id) - 'guest_id'
        = pg_temp.list_row(pg_temp.tx('pl8_list'), (pg_temp.pp(pg_temp.fx('pia'))).free_guest_id) - 'guest_id'
    and pg_temp.list_row(pg_temp.tx('pl8_list'), (pg_temp.pp(pg_temp.fx('pia'))).vip_guest_id)->'days' = to_jsonb(array[pg_temp.d(11), pg_temp.d(12)])
    and (pg_temp.list_row(pg_temp.tx('pl8_list'), (pg_temp.pp(pg_temp.fx('pia'))).vip_guest_id)->>'plan_id')::uuid = pg_temp.fx('plan_pia')
    and pg_temp.tx('pl8_d12_before') = 'refused day_not_chosen' and pg_temp.tx('pl8_d12_after') = 'saved'
    and (pg_temp.tx('pl8_list')::jsonb) @> jsonb_build_object('hours', jsonb_build_object('daily_start', '09:00', 'daily_end', '19:00'),
          'talk_titles_saved', true),
  'PL8 Pia and Ravi buy VIP: Pia''s answers are on her first record and show on her VIP record too (both days); Ravi''s Day 2, refused before, saves once VIP covers it: '
  || pg_temp.tx('pl8_d12_before') || ' / ' || pg_temp.tx('pl8_d12_after'));

-- PL9 not registered any more: taken off the list by staff, or closed; held people answer too (K26)
select pg_temp.as_user('staff');
select public.event_set_guest_cancelled((pg_temp.pp(pg_temp.fx('quin'))).free_guest_id, true, 'Cannot come');
select pg_temp.as_user('owner');
select pg_temp.put('pl9_quin', pg_temp.plan4('ev4', jsonb_build_array(pg_temp.pa(pg_temp.tx('tok:quin'), 4, pg_temp.ans('{"food": "vegan"}'::jsonb))))::text);
select pg_temp.put('pl9_quin_person', pg_temp.person4('ev4', pg_temp.tx('tok:quin'))::text);
select pg_temp.as_user('staff');
select public.event_set_guest_cancelled((pg_temp.pp(pg_temp.fx('quin'))).free_guest_id, false, null);
select pg_temp.as_user('owner');
select pg_temp.put('pl9_quin_back', pg_temp.plan4('ev4', jsonb_build_array(pg_temp.pa(pg_temp.tx('tok:quin'), 4, pg_temp.ans('{"food": "vegan"}'::jsonb))))::text);
-- Held: Hal on Rosa's phone (phone_in_use) and Hed on the Twins' phone; Hal answers, then is linked to Rosa; Hed is closed.
select pg_temp.put('pl9_r', pg_temp.reg4('ev4', 'pl9', jsonb_build_array(
  pg_temp.person(1, 'Hal', 'Heldplan', pg_temp.ph(3), pg_temp.mail('pl-hal'), array[pg_temp.d(11)]),
  pg_temp.person(2, 'Hed', 'Heldclose', pg_temp.ph(5), pg_temp.mail('pl-hed'), array[pg_temp.d(12)])))::text);
select pg_temp.putx(k, pg_temp.pid(pg_temp.tx('pl9_r')::jsonb, n)) from (values ('hal', 1), ('hed', 2)) x(k, n);
select pg_temp.put('tok:' || k, pg_temp.tok(pg_temp.tx('pl9_r')::jsonb, n)) from (values ('hal', 1), ('hed', 2)) x(k, n);
select pg_temp.put('pl9_held', pg_temp.plan4('ev4', jsonb_build_array(
  pg_temp.pa(pg_temp.tx('tok:hal'), 0, pg_temp.ans('{"food": "halal", "allergy": "yes", "allergy_details": "Sesame"}'::jsonb)),
  pg_temp.pa(pg_temp.tx('tok:hed'), 0, pg_temp.ans('{"food": "vegetarian"}'::jsonb))))::text);
select pg_temp.as_user('staff');
select pg_temp.put('pl9_attach', pg_temp.err(format('select public.event_registration_attach(%L, %L, %L)', pg_temp.fx('hal'), pg_temp.fx('c_phone'),
  'Confirmed by phone: the same person')));
select pg_temp.as_user('manager');
select pg_temp.put('pl9_close', pg_temp.err(format('select public.event_registration_close(%L, %L)', pg_temp.fx('hed'), 'A duplicate sign-up')));
select pg_temp.as_user('owner');
select pg_temp.put('pl9_hal_person', pg_temp.person4('ev4', pg_temp.tx('tok:hal'))::text);
select pg_temp.put('pl9_hed', pg_temp.plan4('ev4', jsonb_build_array(pg_temp.pa(pg_temp.tx('tok:hed'), 1, pg_temp.ans('{"food": "vegan"}'::jsonb))))::text);
select pg_temp.check(pg_temp.reason_of(pg_temp.tx('pl9_quin'), 1) = 'refused person_cancelled'
    and pg_temp.pr(pg_temp.tx('pl9_quin'), 1)->'planning'->>'version' = '4'
    and (pg_temp.tx('pl9_quin_person')::jsonb)->>'planning_open' = 'false'
    and pg_temp.reason_of(pg_temp.tx('pl9_quin_back'), 1) = 'saved' and pg_temp.pr(pg_temp.tx('pl9_quin_back'), 1)->'planning'->>'version' = '5',
  'PL9 Quin taken off the list by staff: refused person_cancelled with what is kept (and person says planning_open false); put back: saved again: '
  || pg_temp.tx('pl9_quin'));
select pg_temp.check((pg_temp.pp(pg_temp.fx('hal'))).hold_reason = 'phone_in_use'
    and pg_temp.reason_of(pg_temp.tx('pl9_held'), 1) = 'saved' and pg_temp.reason_of(pg_temp.tx('pl9_held'), 2) = 'saved'
    and (pg_temp.prow((pg_temp.pp(pg_temp.fx('hal'))).free_guest_id)).person_id = pg_temp.fx('hal')
    and not pg_temp.says_who(pg_temp.tx('pl9_held')::jsonb),
  'PL9 people held for staff (Hal on another customer''s phone, Hed on two others'') answer as anyone: kept on their free record, the answer says nothing of the hold: '
  || pg_temp.tx('pl9_held') || ' ' || coalesce((pg_temp.pp(pg_temp.fx('hed'))).hold_reason, '(no hold)'));
select pg_temp.check(pg_temp.tx('pl9_attach') = 'ok' and (pg_temp.pp(pg_temp.fx('hal'))).customer_id = pg_temp.fx('c_phone')
    and (pg_temp.prow((pg_temp.pp(pg_temp.fx('hal'))).free_guest_id)).allergy_details = 'Sesame'
    and (pg_temp.tx('pl9_hal_person')::jsonb)->'planning'->'answers'->>'allergy_details' = 'Sesame'
    and not pg_temp.says_who(pg_temp.tx('pl9_hal_person')::jsonb)
    and pg_temp.tx('pl9_close') = 'ok'
    and pg_temp.pr(pg_temp.tx('pl9_hed'), 1) = jsonb_build_object('person_id', pg_temp.fx('hed'), 'status', 'refused', 'reason', 'person_cancelled',
          'planning', pg_temp.pr(pg_temp.tx('pl9_held'), 2)->'planning'),
  'PL9 Hal linked to a customer keeps his answers (person shows them, nothing of the match); Hed closed by a Manager: person_cancelled with what is kept: '
  || pg_temp.tx('pl9_attach') || ' / ' || pg_temp.tx('pl9_close'));

-- PL10 until the event has ended; the website Off or the event off sale do not stop answers
update event_web_settings set mode = 'off' where event_id = pg_temp.fx('ev4');
update events set is_active = false where id = pg_temp.fx('ev4');
select pg_temp.put('pl10_off_info', pg_temp.info4()::text);
select pg_temp.put('pl10_off', pg_temp.plan4('ev4', jsonb_build_array(pg_temp.pa(pg_temp.tx('tok:sol'), 1,
  pg_temp.ans('{"food": "vegan", "allergy": "no"}'::jsonb))))::text);
update events set is_active = true where id = pg_temp.fx('ev4');
update event_days set day = day - 40 where event_id = pg_temp.fx('ev4');
select pg_temp.put('pl10_off_ended_info', pg_temp.info4()::text);
select pg_temp.put('pl10_off_ended', pg_temp.plan4('ev4', jsonb_build_array(pg_temp.pa(pg_temp.tx('tok:sol'), 2, pg_temp.ans())))::text);
update event_web_settings set mode = 'live' where event_id = pg_temp.fx('ev4');
select pg_temp.put('pl10_info', pg_temp.info4()::text);
select pg_temp.put('pl10_ended', pg_temp.plan4('ev4', jsonb_build_array(pg_temp.pa(pg_temp.tx('tok:sol'), 2, pg_temp.ans())))::text);
select pg_temp.put('pl10_person', pg_temp.person4('ev4', pg_temp.tx('tok:sol'))::text);
update event_days set day = day + 40 where event_id = pg_temp.fx('ev4');
select pg_temp.put('pl10_back', pg_temp.info4()::text);
select pg_temp.check((pg_temp.tx('pl10_off_info')::jsonb)->'event' @> '{"closed_reason": "website_off", "planning_open": true}'::jsonb
    and pg_temp.reason_of(pg_temp.tx('pl10_off'), 1) = 'saved'
    and (pg_temp.tx('pl10_off_ended_info')::jsonb)->'event' @> '{"closed_reason": "website_off", "planning_open": false}'::jsonb
    and (pg_temp.tx('pl10_off_ended')::jsonb) = '{"ok": true, "test": false, "status": "closed", "reason": "ended"}'::jsonb
    and (pg_temp.tx('pl10_info')::jsonb)->'event' @> '{"closed_reason": "ended", "planning_open": false}'::jsonb
    and (pg_temp.tx('pl10_ended')::jsonb) = '{"ok": true, "test": false, "status": "closed", "reason": "ended"}'::jsonb
    and (pg_temp.tx('pl10_person')::jsonb)->>'planning_open' = 'false'
    and (pg_temp.tx('pl10_person')::jsonb)->'planning'->>'version' = '2'
    and (pg_temp.tx('pl10_back')::jsonb)->'event' @> '{"closed_reason": null, "planning_open": true}'::jsonb,
  'PL10 the website Off and the event off sale: answers still saved (event_info planning_open true); once the event has ended (also while Off): the whole call is closed (ended), planning_open false, person keeps showing the answers: '
  || pg_temp.tx('pl10_off_ended'));

-- PL11 the test key: a dry run (what would be kept, nothing kept, nothing audited)
select pg_temp.put('pl11_r', pg_temp.reg4('ev4t', 'pl11', jsonb_build_array(
  pg_temp.person(1, 'Tia', 'Testplan', pg_temp.ph(304), pg_temp.mail('pl-tia'), array[pg_temp.d(11)])))::text);
select pg_temp.put('tok:tia', pg_temp.tok(pg_temp.tx('pl11_r')::jsonb, 1));
select pg_temp.put('pl11_rows', (select count(*) from event_planning_answers)::text);
select pg_temp.put('pl11_audits', (select count(*) from audit_logs where table_name = 'event_planning_answers')::text);
select pg_temp.put('pl11', pg_temp.plan4('ev4t', jsonb_build_array(pg_temp.pa(pg_temp.tx('tok:tia'), 0,
  pg_temp.ans(jsonb_build_object('food', 'halal', 'timing', jsonb_build_array(pg_temp.part(pg_temp.d(11), '13:00', '19:00'))))),
  pg_temp.pa(pg_temp.tx('tok:pia'), 3, pg_temp.ans())))::text);
select pg_temp.put('pl11_again0', pg_temp.reason_of(pg_temp.plan4('ev4t', jsonb_build_array(pg_temp.pa(pg_temp.tx('tok:tia'), 0,
  pg_temp.ans('{"food": "halal"}'::jsonb))))::text, 1));
select pg_temp.put('pl11_again1', pg_temp.plan4('ev4t', jsonb_build_array(pg_temp.pa(pg_temp.tx('tok:tia'), 1,
  pg_temp.ans('{"food": "halal"}'::jsonb))))::text);
select pg_temp.put('pl11_person', pg_temp.person4('ev4t', pg_temp.tx('tok:tia'))::text);
select pg_temp.check((pg_temp.tx('pl11')::jsonb)->>'test' = 'true'
    and pg_temp.pr(pg_temp.tx('pl11'), 1) - 'planning' = jsonb_build_object('person_id', pg_temp.pid(pg_temp.tx('pl11_r')::jsonb, 1), 'status', 'test', 'reason', null)
    and (pg_temp.pr(pg_temp.tx('pl11'), 1)->'planning') - 'updated_at' = jsonb_build_object('version', 1, 'updated_by', 'guest',
          'answers', pg_temp.ans(jsonb_build_object('food', 'halal', 'timing', jsonb_build_array(pg_temp.part(pg_temp.d(11), '13:00', '19:00')))))
    and pg_temp.pr(pg_temp.tx('pl11'), 2) = '{"person_id": null, "status": "refused", "reason": "person_not_found", "planning": null}'::jsonb
    and (select count(*) from event_planning_answers)::text = pg_temp.tx('pl11_rows')
    and (select count(*) from audit_logs where table_name = 'event_planning_answers')::text = pg_temp.tx('pl11_audits')
    and pg_temp.tx('pl11_again0') = 'test'
    and pg_temp.pr(pg_temp.tx('pl11_again1'), 1) - 'person_id' = '{"status": "refused", "reason": "changed_meanwhile", "planning": null}'::jsonb
    and (pg_temp.tx('pl11_person')::jsonb) @> '{"planning": null, "planning_open": true}'::jsonb
    and exists (select 1 from event_web_requests q where q.key_id = pg_temp.fx('key_ev4t') and q.type = 'planning_answers' and q.outcome = 'ok'),
  'PL11 the test key: test with what would be kept (version 1), nothing kept or audited; a live person''s token through it: person_not_found; saved again with version 0: test again; with version 1: changed_meanwhile with nothing kept; its person shows no answers; logged: '
  || pg_temp.tx('pl11'));

-- PL12 answers have their own budget (300 in 10 minutes per key): sign-ups that use up theirs never block them
insert into public.event_web_requests (key_id, request_id, type, is_write, body_md5, outcome, received_at)
select pg_temp.fx('key_ev4'), gen_random_uuid(), 'register', true, 'x', 'registered', now() - interval '9 minutes' from generate_series(1, 120);
select pg_temp.put('pl12_reg', pg_temp.reg4('ev4', 'pl12', jsonb_build_array(
  pg_temp.person(1, 'Bot', 'Planform', pg_temp.ph(305), pg_temp.mail('pl-bot'), array[pg_temp.d(11)])))::text);
select pg_temp.put('pl12_ok', pg_temp.plan4('ev4', jsonb_build_array(pg_temp.pa(pg_temp.tx('tok:sol'), 2,
  pg_temp.ans('{"food": "vegan", "allergy": "no", "heard_from": "facebook"}'::jsonb))))::text);
insert into public.event_web_requests (key_id, request_id, type, is_write, body_md5, outcome, received_at)
select pg_temp.fx('key_ev4'), gen_random_uuid(), 'planning_answers', true, 'x', 'ok', now() - interval '8 minutes'
  from generate_series(1, 300 - (select count(*)::int from event_web_requests where key_id = pg_temp.fx('key_ev4') and type = 'planning_answers'
                                    and received_at > now() - interval '10 minutes'));
select pg_temp.put('pl12_full', pg_temp.plan4('ev4', jsonb_build_array(pg_temp.pa(pg_temp.tx('tok:sol'), 3, pg_temp.ans('{"food": "halal"}'::jsonb))))::text);
select pg_temp.put('pl12_paid_reg', pg_temp.reg4('ev4t', 'pl12t', jsonb_build_array(
  pg_temp.person(1, 'Tim', 'Testbudget', pg_temp.ph(306), pg_temp.mail('pl-tim'), array[pg_temp.d(11)])))::text);
delete from public.event_web_requests where key_id = pg_temp.fx('key_ev4') and body_md5 = 'x';
select pg_temp.check((pg_temp.tx('pl12_reg')::jsonb) @> '{"ok": false, "error": "too_many_requests"}'::jsonb
    and pg_temp.reason_of(pg_temp.tx('pl12_ok'), 1) = 'saved'
    and (pg_temp.tx('pl12_full')::jsonb) @> '{"ok": false, "error": "too_many_requests"}'::jsonb
    and ((pg_temp.tx('pl12_full')::jsonb)->>'retry_after_seconds')::int between 1 and 121
    and (pg_temp.tx('pl12_paid_reg')::jsonb)->>'status' = 'registered',
  'PL12 with the sign-up budget used up, answers still save; the 301st answer in 10 minutes is too_many_requests with when to try again; another key is not affected: '
  || pg_temp.tx('pl12_full'));

-- PL13 the Event page: who sees and changes answers (as the guest list and Save guest), versions, notes, audit
select pg_temp.as_user('staff');
select pg_temp.putx('walt', (public.event_save_guest(jsonb_build_object('event_id', pg_temp.fx('ev4'), 'name', 'Walt Walkin',
  'phone', pg_temp.ph(307), 'days', jsonb_build_array(pg_temp.d(11), pg_temp.d(12))))->>'guest_id')::uuid);
select pg_temp.as_user('owner');
select pg_temp.putx('inv_cvip4', public.create_invoice_with_details(pg_temp.fx('van'), pg_temp.fx('c_ken'),
  jsonb_build_array(jsonb_build_object('kind', 'event_ticket', 'event_ticket_option_id', pg_temp.fx('vip4'), 'quantity', 1,
    'attendees', jsonb_build_array(jsonb_build_object('name', 'Cora Countervip')))), jsonb_build_object('business_date', public.sg_today())));
select pg_temp.putx('cora', (select id from event_guests where invoice_id = pg_temp.fx('inv_cvip4')));
select pg_temp.as_user('staff');
select pg_temp.put('pl13_list_staff', pg_temp.err(format('select public.event_planning_list(%L)', pg_temp.fx('ev4'))));
select pg_temp.put('pl13_walt', public.event_planning_save(pg_temp.fx('walt'), pg_temp.ans(jsonb_build_object('food', 'no_preference',
  'allergy', 'yes', 'allergy_details', 'Penicillin', 'access', '["wheelchair"]'::jsonb, 'question', 'Is there parking?',
  'timing', jsonb_build_array(pg_temp.part(pg_temp.d(12), '09:00', '15:00')))), 0, 'Told by phone')::text);
select pg_temp.put('pl13_cora', public.event_planning_save(pg_temp.fx('cora'), pg_temp.ans(jsonb_build_object('food', 'halal',
  'allergy', 'yes', 'allergy_details', 'Peanuts', 'timing', jsonb_build_array(pg_temp.part(pg_temp.d(11), '11:00', '19:00')))), null, null)::text);
select pg_temp.put('pl13_same', public.event_planning_save(pg_temp.fx('walt'), (pg_temp.tx('pl13_walt')::jsonb)->'answers', 99, 'Again')::text);
select pg_temp.put('pl13_note', pg_temp.err(format('select public.event_planning_save(%L, %L, 1, %L)', pg_temp.fx('walt'),
  pg_temp.ans('{"food": "vegan"}'::jsonb), repeat('n', 201))));
select pg_temp.as_user('manager');
select pg_temp.put('pl13_stale_staff', pg_temp.err(format('select public.event_planning_save(%L, %L, 0, null)', pg_temp.fx('walt'),
  pg_temp.ans('{"food": "vegan"}'::jsonb))));
select pg_temp.put('pl13_stale_web', pg_temp.err(format('select public.event_planning_save(%L, %L, 1, null)',
  (pg_temp.pp(pg_temp.fx('pia'))).vip_guest_id, pg_temp.ans('{"food": "vegan"}'::jsonb))));
-- A Manager changes Pia's answers on her VIP record (told by phone): her page, still on version 3, is told they changed.
select pg_temp.put('pl13_pia_staff', public.event_planning_save((pg_temp.pp(pg_temp.fx('pia'))).vip_guest_id,
  pg_temp.pia_answers() || '{"allergy": "yes", "allergy_details": "Shellfish", "heard_from": "tiktok", "question": "How long should I sleep?"}'::jsonb,
  4, 'Called to add an allergy')::text);
select pg_temp.as_user('owner');
select pg_temp.put('pl13_pia_web', pg_temp.plan4('ev4', jsonb_build_array(pg_temp.pa(pg_temp.tx('tok:pia'), 4,
  pg_temp.pia_answers() || '{"allergy": "no"}'::jsonb)))::text);
select pg_temp.as_user('staff2');
select pg_temp.put('pl13_staff2', pg_temp.errcode(format('select public.event_planning_list(%L)', pg_temp.fx('ev4')))
  || ' ' || pg_temp.errcode(format('select public.event_planning_save(%L, %L, 1, null)', pg_temp.fx('walt'), pg_temp.ans()))
  || ' ' || pg_temp.errcode(format('select public.event_planning_summary(%L)', pg_temp.fx('ev4'))));
select pg_temp.as_user('invmgr');
select pg_temp.put('pl13_invmgr', pg_temp.errcode(format('select public.event_planning_list(%L)', pg_temp.fx('ev4')))
  || ' ' || pg_temp.errcode(format('select public.event_planning_save(%L, %L, 1, null)', pg_temp.fx('walt'), pg_temp.ans()))
  || ' ' || pg_temp.errcode(format('select public.event_planning_summary(%L)', pg_temp.fx('ev4'))));
select pg_temp.as_user('owner');
select pg_temp.check(pg_temp.tx('pl13_list_staff') = 'ok'
    and (pg_temp.tx('pl13_walt')::jsonb) @> jsonb_build_object('ok', true, 'guest_id', pg_temp.fx('walt'), 'changed', true, 'version', 1, 'updated_by', 'staff')
    and (pg_temp.prow(pg_temp.fx('walt'))).staff_id = pg_temp.fx('staff') and (pg_temp.prow(pg_temp.fx('walt'))).person_id is null
    and (pg_temp.tx('pl13_cora')::jsonb) @> '{"ok": true, "changed": true, "version": 1}'::jsonb
    and (pg_temp.tx('pl13_same')::jsonb) @> '{"ok": true, "changed": false, "version": 1}'::jsonb
    and pg_temp.tx('pl13_note') = 'The note is at most 200 characters'
    and pg_temp.tx('pl13_stale_staff') like 'These answers were changed by HT436 Staff % on % since you opened them. Close this and open them again.'
    and pg_temp.tx('pl13_stale_web') like 'These answers were changed by the guest on the website on % since you opened them. Close this and open them again.'
    and exists (select 1 from audit_logs a where a.record_id = (pg_temp.prow(pg_temp.fx('walt'))).id and a.action = 'event_planning_added'
                  and a.changed_by = pg_temp.fx('staff') and a.reason = 'Told by phone'
                  and a.new_data @> '{"source": "staff", "food": "no_preference", "allergy": "yes", "access": ["wheelchair"]}'::jsonb
                  and a.new_data->'texts_changed' = '["allergy_details", "question"]'::jsonb
                  and not (a.new_data ?| array['allergy_details', 'question', 'food_other', 'access_other', 'heard_from_other']))
    and exists (select 1 from audit_logs a where a.record_id = pg_temp.fx('plan_pia') and a.action = 'event_planning_changed'
                  and a.changed_by = pg_temp.fx('manager') and a.reason = 'Called to add an allergy'
                  and a.old_data->>'allergy' = 'no' and a.new_data @> '{"source": "staff", "allergy": "yes", "heard_from": "tiktok", "version": 5}'::jsonb
                  and a.new_data->'texts_changed' = '["allergy_details"]'::jsonb
                  and not (a.new_data ?| array['allergy_details', 'question']) and not (a.old_data ?| array['allergy_details', 'question']))
    and pg_temp.reason_of(pg_temp.tx('pl13_pia_web'), 1) = 'refused changed_meanwhile'
    and pg_temp.pr(pg_temp.tx('pl13_pia_web'), 1)->'planning' @> '{"version": 5, "updated_by": "staff", "answers": {"allergy_details": "Shellfish"}}'::jsonb,
  'PL13 staff answer for a guest staff added and for a counter VIP (audited: who, the note, the old answers); the same answers change nothing; a note of 201 characters is refused; a stale version is refused naming who changed them and when; a Manager adds Pia''s allergy on her VIP record and her page, on the old version, is refused changed_meanwhile with what staff saved: '
  || pg_temp.tx('pl13_stale_staff') || ' / ' || pg_temp.tx('pl13_stale_web'));
select pg_temp.check(pg_temp.tx('pl13_staff2') = '42501 42501 42501' and pg_temp.tx('pl13_invmgr') = '42501 42501 42501',
  'PL13 staff of another store, and an inventory manager of the van (not an event role), are refused (42501) by the list, the save and the summary: '
  || pg_temp.tx('pl13_staff2') || ' / ' || pg_temp.tx('pl13_invmgr'));
-- K27 a counter VIP's answers survive a correction of their invoice that keeps them on the line
do $$ declare it uuid; begin
  perform pg_temp.as_user('owner');
  select id into it from invoice_items where invoice_id = pg_temp.fx('inv_cvip4') and line_kind = 'event_ticket';
  perform public.correct_invoice(pg_temp.fx('inv_cvip4'), jsonb_build_array(jsonb_build_object('kind', 'event_ticket', 'invoice_item_id', it,
    'event_ticket_option_id', pg_temp.fx('vip4'), 'quantity', 1, 'unit_price', 72,
    'event_days', to_jsonb((select event_days from invoice_items where id = it)),
    'attendees', jsonb_build_array(jsonb_build_object('guest_id', pg_temp.fx('cora'), 'name', 'Cora Countervip-Renamed')))),
    '{}'::jsonb, 'PL13 rename', gen_random_uuid());
end $$;
select pg_temp.as_user('staff');
select pg_temp.put('pl13_list', public.event_planning_list(pg_temp.fx('ev4'))::text);
select pg_temp.as_user('owner');
select pg_temp.check((select name from event_guests where id = pg_temp.fx('cora')) = 'Cora Countervip-Renamed'
    and (select status from event_guests where id = pg_temp.fx('cora')) = 'registered'
    and pg_temp.list_row(pg_temp.tx('pl13_list'), pg_temp.fx('cora'))->'answers'->>'allergy_details' = 'Peanuts'
    and pg_temp.list_row(pg_temp.tx('pl13_list'), pg_temp.fx('cora'))->>'staff_name' = 'HT436 Staff ' || pg_temp.tx('sfx'),
  'PL13 a counter VIP''s answers survive an invoice correction that keeps them on the line: still listed on the same guest');

-- PL14 the summary (registered guests; a website VIP once, on their VIP record)
-- Before: a PayNow transfer for Ula (not confirmed) waits; then a Manager confirms it.
select pg_temp.put('pl14_r', pg_temp.reg4('ev4', 'pl14', jsonb_build_array(
  pg_temp.person(1, 'Ula', 'Waitpay', pg_temp.ph(308), pg_temp.mail('pl-ula'), array[pg_temp.d(12)])))::text);
select pg_temp.put('pl14_t', pg_temp.call('ev4', 'vip_transfer', jsonb_build_object('event', pg_temp.tx('code4'), 'order', jsonb_build_object(
  'order_id', pg_temp.bid('VIP', 'pl14'), 'upgrade_tokens', jsonb_build_array(pg_temp.tok(pg_temp.tx('pl14_r')::jsonb, 1)),
  'payer', jsonb_build_object('name', 'Ula Waitpay', 'email', pg_temp.mail('pl-ula'), 'phone', null),
  'method', 'paynow', 'reference', 'PL14 PAYNOW', 'paid_on', public.sg_today(), 'amount_cents', 7200, 'submitted_at', now())))::text);
select pg_temp.as_user('staff');
select pg_temp.put('pl14_wait', public.event_planning_summary(pg_temp.fx('ev4'))::text);
select pg_temp.as_user('manager');
select pg_temp.put('pl14_inv', pg_temp.err(format('select public.event_vip_order_invoice(%L)', (pg_temp.vorder('pl14')).id)));
select pg_temp.as_user('staff');
select pg_temp.put('pl14', public.event_planning_summary(pg_temp.fx('ev4'))::text);
select pg_temp.as_user('staff2');
select pg_temp.put('pl14_staff2', pg_temp.errcode(format('select public.event_planning_summary(%L)', pg_temp.fx('ev4'))));
select pg_temp.as_user('owner');
create function pg_temp.sday(n int) returns jsonb language sql as $$ select (pg_temp.tx('pl14')::jsonb)->'days'->(n - 1) $$;
create function pg_temp.names(list jsonb) returns text language sql as
$$ select string_agg(x->>'name' || coalesce(':' || (x->>'time'), '') || case when (x->>'vip')::boolean then '*' else '' end, ',' order by o)
     from jsonb_array_elements(list) with ordinality t(x, o) $$;
-- Registered on ev4 now: Pia and Ravi (VIP records, both days), Ula (VIP since a Manager confirmed her PayNow, no answers),
-- Cora (counter VIP, both days: halal, Peanuts, from 11:00 am on Day 1), Walt (staff-added, both days: no preference,
-- Penicillin, wheelchair, until 3:00 pm on Day 2), Hal (Day 1: halal, Sesame), Sol (both days: vegan, heard Facebook) and
-- Quin (Day 2: vegan). Pia: vegetarian, Shellfish (staff), from 2:00 pm on Day 1, TikTok, a question. Ravi: no beef, help
-- walking. Hed was closed and the VIPs' free records are parked: none counted.
select pg_temp.check((pg_temp.tx('pl14_wait')::jsonb)->'vip'->>'waiting' = '1'
    and pg_temp.tx('pl14_inv') = 'ok' and (pg_temp.tx('pl14')::jsonb)->'vip'->>'waiting' = '0'
    and (pg_temp.tx('pl14')::jsonb)->'vip'->>'count' = '4'
    and pg_temp.tx('pl14_staff2') = '42501',
  'PL14 a PayNow VIP payment not confirmed yet is counted apart (vip.waiting 1); once a Manager confirms it, it is a VIP (waiting 0); staff of another store cannot read the summary: '
  || ((pg_temp.tx('pl14_wait')::jsonb)->'vip')::text);
select pg_temp.check(pg_temp.sday(1)->'food' = '{"no_preference": 1, "vegetarian": 1, "vegan": 1, "halal": 2, "no_beef": 1, "other": 0, "not_said": 1}'::jsonb
    and pg_temp.sday(1)->>'registered' = '7' and pg_temp.sday(1)->>'answered' = '6'
    and pg_temp.names(pg_temp.sday(1)->'allergies') = 'Cora Countervip-Renamed*,Hal Heldplan,Pia Planner*,Walt Walkin'
    and pg_temp.names(pg_temp.sday(1)->'late') = 'Cora Countervip-Renamed:11:00*,Pia Planner:14:00*'
    and pg_temp.names(pg_temp.sday(1)->'early') is null
    and pg_temp.names(pg_temp.sday(1)->'access') = 'Ravi Planner*,Walt Walkin'
    and pg_temp.sday(2)->>'registered' = '7' and pg_temp.sday(2)->>'answered' = '6'
    and pg_temp.sday(2)->'food' = '{"no_preference": 1, "vegetarian": 1, "vegan": 2, "halal": 1, "no_beef": 1, "other": 0, "not_said": 1}'::jsonb
    and pg_temp.names(pg_temp.sday(2)->'early') = 'Walt Walkin:15:00' and pg_temp.names(pg_temp.sday(2)->'late') is null,
  'PL14 per day: food counts (not said included), allergies (VIPs marked), late and early by time, access needs; a cancelled guest, a closed one and a VIP''s parked free record are not counted: '
  || pg_temp.sday(1)::text);
select pg_temp.check((pg_temp.tx('pl14')::jsonb)->'vip'->'food' = '{"no_preference": 0, "vegetarian": 1, "vegan": 0, "halal": 1, "no_beef": 1, "other": 0, "not_said": 1}'::jsonb
    and (pg_temp.tx('pl14')::jsonb)->'vip'->>'answered' = '3'
    and pg_temp.names((pg_temp.tx('pl14')::jsonb)->'vip'->'allergies') = 'Cora Countervip-Renamed*,Pia Planner*'
    and (pg_temp.tx('pl14')::jsonb)->'talks' = jsonb_build_array(
          jsonb_build_object('title', 'Sleep better, stress less', 'count', 1, 'listed', true),
          jsonb_build_object('title', 'Caring for your eyes', 'count', 1, 'listed', false),
          jsonb_build_object('title', 'Healthy joints, back and muscles', 'count', 0, 'listed', true),
          jsonb_build_object('title', 'Good circulation for everyday energy', 'count', 0, 'listed', true),
          jsonb_build_object('title', 'Caring for your eyes and vision', 'count', 0, 'listed', true),
          jsonb_build_object('title', 'Ageing well and staying active', 'count', 0, 'listed', true),
          jsonb_build_object('title', 'Eating well for long-term health', 'count', 0, 'listed', true),
          jsonb_build_object('title', 'Women''s wellness', 'count', 0, 'listed', true))
    and (pg_temp.tx('pl14')::jsonb)->'heard_from' = '{"tiktok": 1, "facebook": 1, "instagram": 0, "google": 0, "whatsapp": 0, "friend_family": 0, "staff": 0, "email": 0, "other": 0, "not_said": 6}'::jsonb
    and (pg_temp.tx('pl14')::jsonb)->'heard_from_other' = '[]'::jsonb
    and pg_temp.names((pg_temp.tx('pl14')::jsonb)->'questions') = 'Pia Planner*,Walt Walkin'
    and (pg_temp.tx('pl14')::jsonb)->>'registered' = '8' and (pg_temp.tx('pl14')::jsonb)->>'answered' = '7',
  'PL14 the VIPs (Pia, Ravi, Ula and the counter VIP, each once): food and allergies for the dinner; the talks with 0 for unchosen titles and a renamed one "no longer listed"; how they heard; the questions: '
  || ((pg_temp.tx('pl14')::jsonb) - 'days')::text);

-- PL15 the person and the sync carry a website person's answers (by person); staff and counter guests' never leave the app
update event_web_settings set last_sync_at = null, last_test_sync_at = null where event_id = pg_temp.fx('ev4');
select pg_temp.put('pl15_person', pg_temp.person4('ev4', pg_temp.tx('tok:pia'))::text);
select pg_temp.put('pl15_sync', pg_temp.call('ev4', 'sync', jsonb_build_object('event', pg_temp.tx('code4')))::text);
select pg_temp.put('pl15_tsync', pg_temp.call('ev4t', 'sync', jsonb_build_object('event', pg_temp.tx('code4')))::text);
create function pg_temp.sync_row(sync text, nm text) returns jsonb language sql as
$$ select x from jsonb_array_elements((sync::jsonb)->'people') x where x->>'name' = nm $$;
select pg_temp.as_user('staff');
select pg_temp.put('pl15_list', public.event_planning_list(pg_temp.fx('ev4'))::text);
select pg_temp.as_user('owner');
select pg_temp.check((pg_temp.tx('pl15_person')::jsonb)->'planning' = pg_temp.list_row(pg_temp.tx('pl15_list'), (pg_temp.pp(pg_temp.fx('pia'))).vip_guest_id)
          - 'guest_id' - 'plan_id' - 'days' - 'staff_name'
    and (pg_temp.tx('pl15_person')::jsonb)->>'planning_open' = 'true'
    and not exists (select 1 from jsonb_array_elements((pg_temp.tx('pl15_person')::jsonb)->'group') m where m ? 'planning')
    and pg_temp.sync_row(pg_temp.tx('pl15_sync'), 'Pia Planner')->'planning' = (pg_temp.tx('pl15_person')::jsonb)->'planning'
    and pg_temp.sync_row(pg_temp.tx('pl15_sync'), 'Ula Waitpay')->'planning' = 'null'::jsonb
    and pg_temp.sync_row(pg_temp.tx('pl15_sync'), 'Walt Walkin')->'planning' = 'null'::jsonb
    and pg_temp.sync_row(pg_temp.tx('pl15_sync'), 'Cora Countervip-Renamed')->'planning' = 'null'::jsonb
    and (select bool_and(x ? 'planning') from jsonb_array_elements((pg_temp.tx('pl15_sync')::jsonb)->'people') x)
    and (pg_temp.tx('pl15_tsync')::jsonb)->>'status' = 'ok'
    and (select bool_and(x->'planning' = 'null'::jsonb) from jsonb_array_elements((pg_temp.tx('pl15_tsync')::jsonb)->'people') x)
    and pg_temp.tx('pl15_sync') !~ 'plan_id|staff_id|Penicillin',
  'PL15 person: Pia''s own answers (no plan_id or staff_id), the others on her form without any; sync: each website person''s answers by person (none: null); a staff-added guest''s and a counter VIP''s are null even with answers; the test key''s sync null everywhere: '
  || coalesce(pg_temp.sync_row(pg_temp.tx('pl15_sync'), 'Pia Planner')::text, '(no row)'));

-- PL16 privacy: no planning_answers answer says who anyone is, nor carries another person's answers
select pg_temp.check(not exists (select 1 from event_web_requests q where q.key_id in (pg_temp.fx('key_ev4'), pg_temp.fx('key_ev4t'))
                                   and q.type = 'planning_answers' and q.response is not null and pg_temp.says_who(q.response))
    and (select count(*) from event_web_requests q where q.key_id in (pg_temp.fx('key_ev4'), pg_temp.fx('key_ev4t'))
           and q.type = 'planning_answers' and q.response is not null) > 10
    and pg_temp.pr(pg_temp.tx('pl9_held'), 1)->'planning'->'answers'->>'food' = 'halal'
    and pg_temp.pr(pg_temp.tx('pl9_held'), 2)->'planning'->'answers'->>'food' = 'vegetarian'
    and pg_temp.tx('pl9_held') !~ 'Shellfish|Penicillin|Peanuts',
  'PL16 no planning_answers answer names a customer, a match, a hold or a referral; each person''s result carries only their own answers');

-- PL18 when answers close: the event's end (Singapore), whole day without hours; deleted; a person's own state
do $$ declare ev uuid; begin
  insert into events(name, daily_start, daily_end, is_active) values ('HT436 Closing ' || pg_temp.tx('sfx'), '09:00', '19:00', true) returning id into ev;
  insert into fx values ('ev5', ev);
end $$;
select pg_temp.put('pl18_none', coalesce(public.event_web_planning_closed(pg_temp.fx('ev5')), 'open'));
insert into event_days(event_id, day) values (pg_temp.fx('ev5'), pg_temp.d(3));
select pg_temp.put('pl18_live', coalesce(public.event_web_planning_closed(pg_temp.fx('ev5')), 'open'));
update event_days set day = pg_temp.d(-1) where event_id = pg_temp.fx('ev5');
select pg_temp.put('pl18_past', coalesce(public.event_web_planning_closed(pg_temp.fx('ev5')), 'open'));
update events set daily_end = null where id = pg_temp.fx('ev5');
update event_days set day = pg_temp.d(0) where event_id = pg_temp.fx('ev5');
select pg_temp.put('pl18_today_noend', coalesce(public.event_web_planning_closed(pg_temp.fx('ev5')), 'open'));
update event_days set day = pg_temp.d(-1) where event_id = pg_temp.fx('ev5');
select pg_temp.put('pl18_yesterday_noend', coalesce(public.event_web_planning_closed(pg_temp.fx('ev5')), 'open'));
update events set daily_end = '19:00' where id = pg_temp.fx('ev5');
update event_days set day = pg_temp.d(0) where event_id = pg_temp.fx('ev5');
select pg_temp.put('pl18_today', coalesce(public.event_web_planning_closed(pg_temp.fx('ev5')), 'open')
  || ' ' || ((now() at time zone 'Asia/Singapore')::time < time '19:00')::text);
update events set deleted_at = now() where id = pg_temp.fx('ev5');
select pg_temp.put('pl18_deleted', coalesce(public.event_web_planning_closed(pg_temp.fx('ev5')), 'open'));
select pg_temp.check(pg_temp.tx('pl18_none') = 'ended' and pg_temp.tx('pl18_live') = 'open' and pg_temp.tx('pl18_past') = 'ended'
    and pg_temp.tx('pl18_today_noend') = 'open' and pg_temp.tx('pl18_yesterday_noend') = 'ended'
    and pg_temp.tx('pl18_today') in ('open true', 'ended false')
    and pg_temp.tx('pl18_deleted') = 'event_deleted'
    and public.event_web_planning_closed(gen_random_uuid()) = 'event_deleted'
    and public.event_web_planning_closed(pg_temp.fx('ev4')) is null
    and public.event_web_planning_state(pg_temp.fx('hed')) = 'cancelled'
    and public.event_web_planning_state(pg_temp.pid(pg_temp.tx('pl11_r')::jsonb, 1)) = 'open'
    and public.event_web_planning_state(gen_random_uuid()) = 'cancelled',
  'PL18 event_web_planning_closed: no days ended, a later day open, a past day ended, no daily end open all day (today) and ended the day after, today until 7 pm, deleted or unknown event_deleted; the state of a person closed by staff cancelled, of a test person open: '
  || pg_temp.tx('pl18_today'));

-- ═════ PL19-PL22 The review of round 7 (21 Oct 2026) ═════
-- PL19 (K30 amended) a website VIP whose VIP record still stands is counted once, as a VIP, never also as a payment
-- waiting: Ann refunded in full and her invoice reopened; Ben's payment taken off his paid invoice (part paid).
select pg_temp.as_user('owner');
select pg_temp.put('pl19_r', pg_temp.reg4('ev4', 'pl19', jsonb_build_array(
  pg_temp.person(1, 'Ann', 'Twicecount', pg_temp.ph(340), pg_temp.mail('pl19-ann'), array[pg_temp.d(11)]),
  pg_temp.person(2, 'Ben', 'Twicecount', pg_temp.ph(341), pg_temp.mail('pl19-ben'), array[pg_temp.d(12)])))::text);
select pg_temp.putx('pl19_ann', pg_temp.pid(pg_temp.tx('pl19_r')::jsonb, 1));
select pg_temp.putx('pl19_ben', pg_temp.pid(pg_temp.tx('pl19_r')::jsonb, 2));
select pg_temp.put('pl19_save', pg_temp.plan4('ev4', jsonb_build_array(
  pg_temp.pa(pg_temp.tok(pg_temp.tx('pl19_r')::jsonb, 1), 0, pg_temp.ans('{"food": "vegan", "allergy": "yes", "allergy_details": "Kiwi"}'::jsonb))))::text);
select pg_temp.put('pl19_s0', public.event_planning_summary(pg_temp.fx('ev4'))::text);
select pg_temp.checkout4('ev4', 'pl19a', array[pg_temp.tok(pg_temp.tx('pl19_r')::jsonb, 1)]) is not null,
       pg_temp.checkout4('ev4', 'pl19b', array[pg_temp.tok(pg_temp.tx('pl19_r')::jsonb, 2)]) is not null;
select pg_temp.put('pl19_paid', ((pg_temp.paid4('ev4', 'pl19a', array[pg_temp.tok(pg_temp.tx('pl19_r')::jsonb, 1)], 7200))->>'status')
  || ' ' || ((pg_temp.paid4('ev4', 'pl19b', array[pg_temp.tok(pg_temp.tx('pl19_r')::jsonb, 2)], 7200))->>'status'));
select pg_temp.as_user('owner');
select pg_temp.put('pl19_s1', public.event_planning_summary(pg_temp.fx('ev4'))::text);
select pg_temp.putx('pl19_inv_ann', (select i.id from pg_temp.vinvoices('pl19a') i));
select pg_temp.putx('pl19_inv_ben', (select i.id from pg_temp.vinvoices('pl19b') i));
select pg_temp.put('pl19_refund', pg_temp.err(format('select public.refund_invoice_recorded(%L, %L, %L, %L, %L, %L)', pg_temp.fx('pl19_inv_ann'),
  jsonb_build_array(jsonb_build_object('invoice_item_id', pg_temp.ticket(pg_temp.fx('pl19_inv_ann')), 'amount', 72)),
  jsonb_build_array(jsonb_build_object('payment_id', pg_temp.payment(pg_temp.fx('pl19_inv_ann')), 'amount', 72)), '[]', 'PL19 refund in full',
  gen_random_uuid())));
select pg_temp.put('pl19_reopen', pg_temp.err(format('select public.reopen_invoice(%L, %L, %L)', pg_temp.fx('pl19_inv_ann'),
  'PL19 refunded by mistake', gen_random_uuid())));
select pg_temp.put('pl19_remove', pg_temp.err(format('select public.remove_invoice_payment(%L, %L, %L)', pg_temp.payment(pg_temp.fx('pl19_inv_ben')),
  'PL19 payment entered on the wrong invoice', gen_random_uuid())));
select pg_temp.put('pl19_s2', public.event_planning_summary(pg_temp.fx('ev4'))::text);
select pg_temp.check(pg_temp.tx('pl19_paid') = 'invoiced invoiced'
    and pg_temp.tx('pl19_refund') = 'ok' and pg_temp.tx('pl19_reopen') = 'ok' and pg_temp.tx('pl19_remove') = 'ok'
    and public.event_web_person_vip_state(pg_temp.fx('pl19_ann')) = 'pending'
    and public.event_web_person_vip_state(pg_temp.fx('pl19_ben')) = 'pending'
    and (pg_temp.guest((pg_temp.pp(pg_temp.fx('pl19_ann'))).vip_guest_id)).status = 'registered'
    and (pg_temp.guest((pg_temp.pp(pg_temp.fx('pl19_ben'))).vip_guest_id)).status = 'registered'
    and ((pg_temp.tx('pl19_s1')::jsonb)->'vip'->>'count')::int = ((pg_temp.tx('pl19_s0')::jsonb)->'vip'->>'count')::int + 2
    and ((pg_temp.tx('pl19_s2')::jsonb)->'vip'->>'count')::int = ((pg_temp.tx('pl19_s1')::jsonb)->'vip'->>'count')::int
    and (pg_temp.tx('pl19_s2')::jsonb)->'vip'->>'waiting' = (pg_temp.tx('pl19_s1')::jsonb)->'vip'->>'waiting'
    and (pg_temp.tx('pl19_s2')::jsonb)->'vip'->>'waiting' = (pg_temp.tx('pl19_s0')::jsonb)->'vip'->>'waiting'
    and (select count(*) from jsonb_array_elements((pg_temp.tx('pl19_s2')::jsonb)->'vip'->'allergies') x where x->>'name' = 'Ann Twicecount') = 1,
  'PL19 Ann (refunded in full, then reopened) and Ben (his payment taken off) are pending but their VIP records stand: counted once each, as VIPs, not also as payments waiting: '
  || (((pg_temp.tx('pl19_s2')::jsonb)->'vip') - 'food' - 'food_other' - 'allergies')::text || ' ' || pg_temp.tx('pl19_refund') || ' ' || pg_temp.tx('pl19_reopen') || ' ' || pg_temp.tx('pl19_remove'));

-- PL20 the test key's VIP (a test checkout, then vip_paid with livemode false) comes every day, as a live VIP record does:
-- person shows both days and a Day 2 answer is a test (what would be kept), not day_not_chosen.
select pg_temp.put('pl20_r', pg_temp.reg4('ev4t', 'pl20', jsonb_build_array(
  pg_temp.person(1, 'Tara', 'Testvip', pg_temp.ph(342), pg_temp.mail('pl20-tara'), array[pg_temp.d(11)])))::text);
select pg_temp.put('pl20_co', (pg_temp.call('ev4t', 'vip_checkout', jsonb_build_object('event', pg_temp.tx('code4'), 'order', jsonb_build_object(
     'order_id', pg_temp.bid('VIP', 'pl20'), 'upgrade_tokens', jsonb_build_array(pg_temp.tok(pg_temp.tx('pl20_r')::jsonb, 1)),
     'payer', jsonb_build_object('name', 'Payer pl20', 'email', pg_temp.mail('payer-pl20'), 'phone', null),
     'livemode', false, 'checkout_opened_at', now() - interval '3 minutes'))))->>'status');
select pg_temp.put('pl20_paid', pg_temp.call('ev4t', 'vip_paid', jsonb_build_object('event', pg_temp.tx('code4'), 'payment', jsonb_build_object(
     'order_id', pg_temp.bid('VIP', 'pl20'), 'provider', 'hitpay', 'payment_request_id', gen_random_uuid(), 'payment_id', gen_random_uuid(),
     'amount_cents', 7200, 'currency', 'SGD', 'livemode', false, 'paid_at', now() - interval '1 minute',
     'upgrade_tokens', jsonb_build_array(pg_temp.tok(pg_temp.tx('pl20_r')::jsonb, 1)),
     'payer', jsonb_build_object('name', 'Payer pl20', 'email', pg_temp.mail('payer-pl20'), 'phone', null))))::text);
select pg_temp.put('pl20_person', pg_temp.person4('ev4t', pg_temp.tok(pg_temp.tx('pl20_r')::jsonb, 1))::text);
select pg_temp.put('pl20_plan', pg_temp.plan4('ev4t', jsonb_build_array(pg_temp.pa(pg_temp.tok(pg_temp.tx('pl20_r')::jsonb, 1), 0,
  pg_temp.ans(jsonb_build_object('timing', jsonb_build_array(pg_temp.whole(pg_temp.d(11)), pg_temp.part(pg_temp.d(12), '09:00', '15:00')))))))::text);
select pg_temp.put('pl20_free', pg_temp.reg4('ev4t', 'pl20u', jsonb_build_array(
  pg_temp.person(1, 'Uma', 'Testfree', pg_temp.ph(343), pg_temp.mail('pl20-uma'), array[pg_temp.d(11)])))::text);
select pg_temp.put('pl20_free_plan', pg_temp.plan4('ev4t', jsonb_build_array(pg_temp.pa(pg_temp.tok(pg_temp.tx('pl20_free')::jsonb, 1), 0,
  pg_temp.ans(jsonb_build_object('timing', jsonb_build_array(pg_temp.whole(pg_temp.d(12)))))))) ::text);
select pg_temp.check((pg_temp.vorder('pl20')).status = 'test' and (pg_temp.vorder('pl20')).test_would = 'invoiced'
    and (pg_temp.tx('pl20_person')::jsonb)->'person'->>'vip' = 'paid'
    and (pg_temp.tx('pl20_person')::jsonb)->'person'->'days' = jsonb_build_array(pg_temp.d(11), pg_temp.d(12))
    and pg_temp.reason_of(pg_temp.tx('pl20_plan'), 1) = 'test'
    and pg_temp.pr(pg_temp.tx('pl20_plan'), 1)->'planning'->'answers'->'timing'->1 = pg_temp.part(pg_temp.d(12), '09:00', '15:00')
    and pg_temp.reason_of(pg_temp.tx('pl20_free_plan'), 1) = 'refused day_not_chosen'
    and not exists (select 1 from event_planning_answers a where a.person_id = pg_temp.pid(pg_temp.tx('pl20_r')::jsonb, 1)),
  'PL20 a test-key VIP (the dry run''s) shows both days and a Day 2 part day is a test (what would be kept, nothing kept), as a live VIP''s is saved; a test-key free person''s other day is still day_not_chosen: '
  || ((pg_temp.tx('pl20_person')::jsonb)->'person')::text || ' ' || pg_temp.reason_of(pg_temp.tx('pl20_plan'), 1));

-- PL21 a talk title changed only in its capitals keeps its count: the summary compares titles ignoring case, as the check
-- does (no "no longer listed" row for it). ev4's titles are put back afterwards.
select pg_temp.put('pl21_prev', (select coalesce(to_jsonb(talk_titles), 'null'::jsonb)::text from event_web_settings where event_id = pg_temp.fx('ev4')));
select pg_temp.as_user('manager');
select pg_temp.put('pl21_set1', public.event_web_set_talks(pg_temp.fx('ev4'), '["Sleep better, stress less", "Caring for your eyes"]')->>'ok');
select pg_temp.as_user('owner');
select pg_temp.put('pl21_r', pg_temp.reg4('ev4', 'pl21', jsonb_build_array(
  pg_temp.person(1, 'Kim', 'Talkcase', pg_temp.ph(344), pg_temp.mail('pl21-kim'), array[pg_temp.d(11)]),
  pg_temp.person(2, 'Lou', 'Talkcase', pg_temp.ph(345), pg_temp.mail('pl21-lou'), array[pg_temp.d(11)])))::text);
select pg_temp.put('pl21_save', pg_temp.plan4('ev4', jsonb_build_array(
  pg_temp.pa(pg_temp.tok(pg_temp.tx('pl21_r')::jsonb, 1), 0, pg_temp.ans('{"talks": ["Sleep better, stress less"]}'::jsonb)),
  pg_temp.pa(pg_temp.tok(pg_temp.tx('pl21_r')::jsonb, 2), 0, pg_temp.ans('{"talks": ["Sleep better, stress less", "Caring for your eyes"]}'::jsonb))))::text);
select pg_temp.put('pl21_before', public.event_planning_summary(pg_temp.fx('ev4'))->>'talks');
select pg_temp.as_user('manager');
select pg_temp.put('pl21_set2', public.event_web_set_talks(pg_temp.fx('ev4'), '["Sleep Better, Stress Less", "Caring for your eyes"]')->>'ok');
select pg_temp.as_user('owner');
select pg_temp.put('pl21_after', public.event_planning_summary(pg_temp.fx('ev4'))->>'talks');
create function pg_temp.talk_count(talks text, title text, listed boolean) returns int language sql as
$$ select (x->>'count')::int from jsonb_array_elements(talks::jsonb) x where x->>'title' = title and (x->>'listed')::boolean = listed $$;
select pg_temp.check(pg_temp.tx('pl21_set1') = 'true' and pg_temp.tx('pl21_set2') = 'true'
    and pg_temp.reason_of(pg_temp.tx('pl21_save'), 1) = 'saved' and pg_temp.reason_of(pg_temp.tx('pl21_save'), 2) = 'saved'
    and pg_temp.talk_count(pg_temp.tx('pl21_before'), 'Sleep better, stress less', true) >= 2
    and pg_temp.talk_count(pg_temp.tx('pl21_after'), 'Sleep Better, Stress Less', true)
        = pg_temp.talk_count(pg_temp.tx('pl21_before'), 'Sleep better, stress less', true)
    and pg_temp.talk_count(pg_temp.tx('pl21_after'), 'Caring for your eyes', true)
        = pg_temp.talk_count(pg_temp.tx('pl21_before'), 'Caring for your eyes', true)
    and not exists (select 1 from jsonb_array_elements(pg_temp.tx('pl21_after')::jsonb) x
                     where not (x->>'listed')::boolean and lower(x->>'title') in ('sleep better, stress less', 'caring for your eyes'))
    and jsonb_array_length(pg_temp.tx('pl21_after')::jsonb) = 2 + (select count(*) from jsonb_array_elements(pg_temp.tx('pl21_after')::jsonb) x
                                                                   where not (x->>'listed')::boolean),
  'PL21 the titles changed only in their capitals: the count stays on the listed title, no "no longer listed" row for it: '
  || pg_temp.tx('pl21_after'));
update event_web_settings set talk_titles = (select case when pg_temp.tx('pl21_prev') = 'null' then null
                                                         else array(select jsonb_array_elements_text(pg_temp.tx('pl21_prev')::jsonb)) end)
 where event_id = pg_temp.fx('ev4');

-- PL22 no planning audit row holds a free text (allergy details, the other food, access and how-heard texts, the
-- question): Owners, Admins and Managers of every store read the audit log; each row says which texts changed.
select pg_temp.check((select count(*) from audit_logs a where a.table_name = 'event_planning_answers') > 10
    and not exists (select 1 from audit_logs a where a.table_name = 'event_planning_answers'
                      and (coalesce(a.old_data, '{}'::jsonb) ?| array['allergy_details', 'question', 'food_other', 'access_other', 'heard_from_other']
                           or coalesce(a.new_data, '{}'::jsonb) ?| array['allergy_details', 'question', 'food_other', 'access_other', 'heard_from_other']
                           or (coalesce(a.old_data::text, '') || coalesce(a.new_data::text, '')) ~ 'Penicillin|Shellfish|Peanuts|Sesame|Kiwi|parking|How long should'))
    and not exists (select 1 from audit_logs a where a.table_name = 'event_planning_answers' and jsonb_typeof(a.new_data->'texts_changed') <> 'array')
    and exists (select 1 from audit_logs a where a.record_id = pg_temp.fx('plan_pia') and a.action = 'event_planning_added'
                  and a.new_data->'texts_changed' = '[]'::jsonb),
  'PL22 the planning audit rows keep who, when and the choices, and which free texts changed (texts_changed), never the texts');

-- ═════ RQ The owner's answers to round 6's questions (21 Oct 2026, "go with what you recommend") ═════
-- RQ1 (R6-1) Someone held only for another customer's email inbox (no shared phone), through the link: made a customer they wait
-- for the check like answer 2 (no referrer, a pending check sharing with that customer, the note says so); Ivo is checked
-- as a different person: referred, his VIP paid meanwhile earns once (R6-5: dated the day of the check, in Singapore);
-- Ida is checked as the same person: nothing.
select pg_temp.as_user('owner');
do $$ declare a uuid; begin
  insert into customers(full_name, phone, email, referred_by) values ('Aff Mailcheck', pg_temp.ph(331), pg_temp.mail('aff-mail'), pg_temp.fx('upline'))
  returning id into a;
  insert into customer_affiliates(customer_id, status, referral_code) values (a, 'active', 'HM' || pg_temp.tx('sfx'));
  insert into fx values ('aff_mail', a);
  insert into tx values ('code_mail', 'HM' || pg_temp.tx('sfx'));
end $$;
select pg_temp.put('r61', pg_temp.register('live', 'r61', jsonb_build_array(
  pg_temp.person(1, 'Ivo', 'Mailshare', pg_temp.ph(320), upper('old-' || pg_temp.mail('weijie')), array[pg_temp.d(7)])), pg_temp.tx('code_mail'))::text);
select pg_temp.put('r61b', pg_temp.register('live', 'r61b', jsonb_build_array(
  pg_temp.person(1, 'Ida', 'Mailshare', pg_temp.ph(321), 'old-' || pg_temp.mail('weijie'), array[pg_temp.d(8)])), pg_temp.tx('code_mail'))::text);
select pg_temp.putx('ivo', pg_temp.pid(pg_temp.tx('r61')::jsonb, 1));
select pg_temp.putx('ida', pg_temp.pid(pg_temp.tx('r61b')::jsonb, 1));
create function pg_temp.mail_note(aff text, code text) returns text language sql as
$$ select format('Their email inbox is on another customer''s record. If this is that customer, link their record: an existing '
                 || 'customer is not referred through this link (%s). If it is someone else, make a new customer: they become %s''s '
                 || 'referral once an Owner or Manager checks them as a different person (Affiliates page), and no commission comes '
                 || 'before that.', code, aff) $$;
create function pg_temp.mail_waiting_note(aff text, code text) returns text language sql as
$$ select format('Waiting for a check: their email inbox is on another customer''s record. They become %s''s referral (link %s) '
                 || 'once an Owner or Manager checks them as a different person (Affiliates page); no commission comes before that.', aff, code) $$;
select pg_temp.put('r61_held_note', public.event_web_referral_note(pg_temp.fx('ivo')));
select pg_temp.as_user('staff');
select pg_temp.put('r61_make', pg_temp.err(format('select public.event_registration_create_customer(%L, %L)', pg_temp.fx('ivo'), 'Not Wei Jie: a colleague using his address')));
select pg_temp.put('r61_make_ida', pg_temp.err(format('select public.event_registration_create_customer(%L, %L)', pg_temp.fx('ida'), 'Says she is new')));
select pg_temp.as_user('owner');
select pg_temp.putx('ivo_c', (pg_temp.pp(pg_temp.fx('ivo'))).customer_id);
select pg_temp.putx('ida_c', (pg_temp.pp(pg_temp.fx('ida'))).customer_id);
select pg_temp.check((pg_temp.pp(pg_temp.fx('ivo'))).hold_reason = 'email_in_use' and (pg_temp.pp(pg_temp.fx('ivo'))).referral_outcome = 'check_waiting'
    and pg_temp.tx('r61_held_note') = pg_temp.mail_note('Aff Mailcheck', pg_temp.tx('code_mail'))
    and pg_temp.tx('r61_make') = 'ok' and pg_temp.tx('r61_make_ida') = 'ok'
    and (select referred_by from customers where id = pg_temp.fx('ivo_c')) is null
    and exists (select 1 from referral_signup_checks k where k.customer_id = pg_temp.fx('ivo_c') and k.status = 'pending'
                  and k.referrer_customer_id = pg_temp.fx('aff_mail') and pg_temp.fx('c_words') = any (k.phone_shared_with)
                  and not (pg_temp.fx('aff_mail') = any (k.phone_shared_with)))
    and exists (select 1 from referral_signup_events e where e.new_customer_id = pg_temp.fx('ivo_c') and e.outcome = 'phone_shared')
    and exists (select 1 from audit_logs a where a.record_id = pg_temp.fx('ivo_c') and a.action = 'referral_check_waiting'
                  and a.reason = 'Their email inbox is on another customer''s record: referred once an Owner or Manager checks them as a different person')
    and public.event_web_referral_note(pg_temp.fx('ivo')) = pg_temp.mail_waiting_note('Aff Mailcheck', pg_temp.tx('code_mail'))
    and (pg_temp.pp(pg_temp.fx('ida'))).referral_outcome = 'check_waiting',
  'RQ1 (R6-1) held only for another customer''s email inbox (no shared phone), through the link: the note says what to do; made a customer, they wait for the check (no referrer, 392''s phone_shared event, a pending check sharing with that customer, audited), as on another customer''s phone: '
  || coalesce(pg_temp.tx('r61_held_note'), '(no note)'));
select pg_temp.checkout('live', 'r61', array[pg_temp.tok(pg_temp.tx('r61')::jsonb, 1)]);
select pg_temp.put('r61_paid', pg_temp.paid('live', 'r61', array[pg_temp.tok(pg_temp.tx('r61')::jsonb, 1)], 7200)::text);
select pg_temp.checkout('live', 'r61b', array[pg_temp.tok(pg_temp.tx('r61b')::jsonb, 1)]);
select pg_temp.put('r61b_paid', pg_temp.paid('live', 'r61b', array[pg_temp.tok(pg_temp.tx('r61b')::jsonb, 1)], 7200)::text);
select pg_temp.putx('ivo_inv', (select i.id from pg_temp.vinvoices('r61') i));
select pg_temp.putx('ida_inv', (select i.id from pg_temp.vinvoices('r61b') i));
-- (one transaction is one moment: Ivo's VIP is dated as paid 40 days ago, in a month that may be paid out already)
update invoices set paid_at = now() - interval '40 days' where id = pg_temp.fx('ivo_inv');
select pg_temp.put('r61_wait_comm', pg_temp.fa_comm(pg_temp.fx('ivo_inv'))::text);
select pg_temp.as_user('staff');
select pg_temp.put('r61_staff', pg_temp.err(format('select public.decide_referral_signup_check(%L, %L, %L)',
  (pg_temp.fa_check(pg_temp.fx('ivo_c'))).id, 'different_person', 'Staff try')));
select pg_temp.as_user('owner');
select pg_temp.put('r61_decide', public.decide_referral_signup_check((pg_temp.fa_check(pg_temp.fx('ivo_c'))).id, 'different_person',
  'A colleague of Wei Jie, his own phone')::text);
select pg_temp.as_user('manager');
select pg_temp.put('r61_decide_ida', public.decide_referral_signup_check((pg_temp.fa_check(pg_temp.fx('ida_c'))).id, 'same_person',
  'Wei Jie''s wife, who is already on his record')::text);
select pg_temp.as_user('owner');
select pg_temp.check((pg_temp.tx('r61_paid')::jsonb)->>'status' = 'invoiced' and pg_temp.tx('r61_wait_comm') = '[]'
    and pg_temp.tx('r61_staff') <> 'ok' and (pg_temp.tx('r61_decide')::jsonb)->>'ok' = 'true'
    and (select (referred_by, referral_source, referral_code_used) = (pg_temp.fx('aff_mail'), 'affiliate_link', pg_temp.tx('code_mail'))
           from customers where id = pg_temp.fx('ivo_c'))
    and (pg_temp.pp(pg_temp.fx('ivo'))).referral_outcome = 'check_confirmed'
    and pg_temp.fa_comm(pg_temp.fx('ivo_inv'))
        = jsonb_build_array(jsonb_build_array('tier1', pg_temp.fx('aff_mail'), 10.80), jsonb_build_array('tier2', pg_temp.fx('upline'), 0.54))
    and (select bool_and(c.invoice_paid_date = public.sg_today()) from commissions c where c.invoice_id = pg_temp.fx('ivo_inv'))
    and (select (paid_at at time zone 'Asia/Singapore')::date from invoices where id = pg_temp.fx('ivo_inv')) = public.sg_today() - 40,
  'RQ1 (R6-1, R6-5) the VIP paid while Ivo waited earned nothing; staff cannot decide; an Owner checks him as a different person: referred, and that VIP earns S$10.80 and S$0.54 once, dated the day of the check (Singapore), not the day it was paid 40 days ago: '
  || pg_temp.tx('r61_decide'));
select pg_temp.check((pg_temp.tx('r61b_paid')::jsonb)->>'status' = 'invoiced' and (pg_temp.tx('r61_decide_ida')::jsonb)->>'ok' = 'true'
    and (select referred_by from customers where id = pg_temp.fx('ida_c')) is null
    and (pg_temp.pp(pg_temp.fx('ida'))).referral_outcome = 'check_same_person'
    and pg_temp.fa_comm(pg_temp.fx('ida_inv')) = '[]'::jsonb,
  'RQ1 (R6-1) Ida, held for the same inbox, checked by a Manager as the same person: never referred, her VIP earns nothing');
-- RQ5 (R6-5) also for Hana (FQ2): her VIP's commission is dated the day of her check.
select pg_temp.check((select bool_and(c.invoice_paid_date = public.sg_today()) from commissions c where c.invoice_id = pg_temp.fx('fq_inv_hana'))
    and (select count(*) from commissions c where c.invoice_id = pg_temp.fx('fq_inv_hana')) = 2,
  'RQ5 (R6-5) Hana''s commission (FQ2) carries the day of the check');

-- RQ7 (R6-7, XR10) a SAVE72 given while the VIP invoice stood paid, before it was cancelled, still counts once it is reopened
-- and paid again: Refund in full and Cancel then need the Owner's or Manager's override, and the Finance panel refuses it.
-- (one transaction is one moment: written as it happens, cancelled a minute after the SAVE72 was given, reopened a minute
-- after that)
select pg_temp.as_user('owner');
insert into customers(full_name, phone) values ('Rhea Reopened', pg_temp.ph(330));
select pg_temp.putx('rhea_c', (select id from customers where full_name = 'Rhea Reopened' and deleted_at is null order by created_at desc limit 1));
select pg_temp.putx('inv_rhea', pg_temp.counter_vip(pg_temp.fx('rhea_c'), array[pg_temp.fx('save72'), pg_temp.fx('three')]));
select pg_temp.putx('xr10_before', pg_temp.save72_invoice(pg_temp.fx('rhea_c'), 'invoice'));
select pg_temp.put('xr10_cancel', pg_temp.err(format('select public.cancel_invoice_recorded(%L, %L, %L)', pg_temp.fx('inv_rhea'), 'Wrong day', gen_random_uuid())));
update audit_logs set created_at = now() + interval '1 minute' where record_id = pg_temp.fx('inv_rhea') and action = 'invoice_cancelled';
select pg_temp.put('xr10_seen_cancelled', coalesce(public.event_vip_used_later(pg_temp.fx('inv_rhea'))->>'invoice_no', 'none'));
select public.reopen_invoice(pg_temp.fx('inv_rhea'), 'Cancelled by mistake', gen_random_uuid());
update audit_logs set created_at = now() + interval '2 minutes' where record_id = pg_temp.fx('inv_rhea') and action = 'invoice_reopened';
select pg_temp.put('xr10_status', (select status::text || ' ' || paid_amount from invoices where id = pg_temp.fx('inv_rhea')));
select pg_temp.as_user('staff');
select pg_temp.put('xr10_full', public.invoice_action_plan(pg_temp.fx('inv_rhea'), 'refund_full', '[]')::text);
select pg_temp.put('xr10_cancel_plan', public.invoice_action_plan(pg_temp.fx('inv_rhea'), 'cancel', '[]')::text);
select pg_temp.as_user('owner');
select pg_temp.put('xr10_panel', pg_temp.panel_refund(pg_temp.fx('inv_rhea'), 72, 'Refund the VIP'));
select pg_temp.check(pg_temp.tx('xr10_cancel') = 'ok' and pg_temp.tx('xr10_seen_cancelled') = pg_temp.ino(pg_temp.fx('xr10_before'))
    and pg_temp.tx('xr10_status') = 'paid 72.00'
    and pg_temp.later_ov_is(pg_temp.tx('xr10_full'), 'Rhea Reopened', 'HT436 $72 discount Voucher', pg_temp.fx('xr10_before'), pg_temp.fx('inv_rhea'))
    and pg_temp.later_ov(pg_temp.tx('xr10_cancel_plan')) = pg_temp.later_ov(pg_temp.tx('xr10_full'))
    and pg_temp.tx('xr10_panel') = pg_temp.later_err_msg('Rhea Reopened', 'HT436 $72 discount Voucher', pg_temp.fx('xr10_before'), pg_temp.fx('inv_rhea'))
    and (select paid_amount from invoices where id = pg_temp.fx('inv_rhea')) = 72,
  'RQ7 (R6-7, XR10) Rhea: SAVE72 given before her VIP invoice was cancelled still counts after it was reopened (paid again): Refund in full and Cancel carry the override, the Finance panel refuses the full refund: '
  || coalesce(pg_temp.later_ov(pg_temp.tx('xr10_full'))::text, 'null') || ' / ' || pg_temp.tx('xr10_panel'));
select pg_temp.as_user('owner');

-- RQ7b (R6-7) one VIP of two refunded leaves the other's time running: a counter VIP for Uri and Vi on two lines; Vi's line
-- refunded in full (436 notes 1 of the 2 tickets); SAVE72 given to Uri after that still counts for Uri's full refund.
-- (written as it happens: Vi's refund a minute before the SAVE72)
insert into customers(full_name, phone) values ('Uri Stillvip', pg_temp.ph(332)), ('Vi Leftearly', pg_temp.ph(333));
select pg_temp.putx(k, (select id from customers where full_name = n and deleted_at is null order by created_at desc limit 1))
  from (values ('uri', 'Uri Stillvip'), ('vi', 'Vi Leftearly')) x(k, n);
select pg_temp.putx('inv_uri', pg_temp.counter_vip_two(pg_temp.fx('uri'), jsonb_build_array(pg_temp.vip_ticket(1, array['uri']), pg_temp.vip_ticket(1, array['vi']))));
select pg_temp.put('rq7b_vi', pg_temp.line_refund(pg_temp.fx('inv_uri'), pg_temp.ticket_of(pg_temp.fx('inv_uri'), 'vi'), 72));
update audit_logs set created_at = now() - interval '1 minute' where record_id = pg_temp.fx('inv_uri') and action = 'vip_refund_vouchers';
select pg_temp.putx('rq7b_later', pg_temp.save72_invoice(pg_temp.fx('uri'), 'invoice'));
select pg_temp.as_user('staff');
select pg_temp.put('rq7b_plan', public.invoice_action_plan(pg_temp.fx('inv_uri'), 'refund_full', '[]')::text);
select pg_temp.as_user('owner');
select pg_temp.check(pg_temp.tx('rq7b_vi') = 'ok'
    and (select a.new_data->>'tickets' || '/' || (a.new_data->>'tickets_refunded') from audit_logs a
          where a.record_id = pg_temp.fx('inv_uri') and a.action = 'vip_refund_vouchers') = '2/1'
    and pg_temp.later_ov_is(pg_temp.tx('rq7b_plan'), 'Uri Stillvip', 'HT436 $72 discount Voucher', pg_temp.fx('rq7b_later'), pg_temp.fx('inv_uri')),
  'RQ7 (R6-7) one VIP of two refunded in full leaves the other''s time running: SAVE72 given to Uri after Vi''s refund still needs the override for Uri''s full refund: '
  || coalesce(pg_temp.later_ov(pg_temp.tx('rq7b_plan'))::text, 'null'));
select pg_temp.as_user('owner');

-- ═════ DV Two VIP payments for one customer (the owner, 21 Oct 2026, round 8: P1) ═════
-- A dedicated event ev5 (two days, Van, VIP S$72 both days, Live), so every count is exact. Dora (on record)
-- registers and pays VIP by HitPay; Cole (on record) too, and then has a VIP ticket at the counter not paid yet (two);
-- Dee registers on Dora's phone under her own name (held) and sends a PayNow transfer; Kai is held on Rosa's phone
-- (Rosa is no guest of ev5). Staff link Dee to Dora (warned by the page first); a Manager confirms Dee's transfer;
-- the Owner cancels one of Dora's two VIP invoices.
select pg_temp.as_user('owner');
create function pg_temp.call5(typ text, body jsonb) returns jsonb language sql as
$$ select pg_temp.call('evd', typ, jsonb_build_object('event', pg_temp.tx('coded')) || body) $$;
create function pg_temp.holds5(answer text) returns jsonb language sql as
$$ select coalesce(jsonb_object_agg(h->>'full_name', h), '{}'::jsonb) from jsonb_array_elements((answer::jsonb)->'holds') h $$;
create function pg_temp.cand5(answer text, held text, cust uuid) returns jsonb language sql as
$$ select c from jsonb_array_elements(pg_temp.holds5(answer)->held->'candidates') c where (c->>'customer_id')::uuid = cust $$;
create function pg_temp.dbl5(answer text, gid uuid) returns boolean language sql as
$$ select (g->>'vip_double')::boolean from jsonb_array_elements((answer::jsonb)->'guests') g where (g->>'guest_id')::uuid = gid $$;
create function pg_temp.inv5(pid uuid) returns text language sql as
$$ select i.invoice_no from public.event_vip_order_people op join public.event_vip_orders o on o.id = op.order_ref
     join public.invoices i on i.id = op.invoice_id where op.person_id = pid and o.status = 'invoiced'
    order by o.created_at desc limit 1 $$;
do $$ declare ev uuid; r jsonb; c uuid; begin
  ev := public.event_save(jsonb_build_object('name', 'HT436 Double VIP ' || pg_temp.tx('sfx'), 'daily_start', '09:00', 'daily_end', '19:00',
    'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(15)), jsonb_build_object('day', pg_temp.d(16))),
    'store_ids', jsonb_build_array(pg_temp.fx('van')),
    'options', jsonb_build_array(jsonb_build_object('name', 'VIP', 'days_count', 2, 'price', 72))));
  insert into fx values ('evd', ev), ('vipd', (select id from public.event_ticket_options where event_id = ev));
  insert into tx values ('coded', 'HT436W-' || pg_temp.tx('sfx'));
  perform public.event_web_settings_save(ev, pg_temp.settings('off', pg_temp.tx('coded')) || jsonb_build_object('vip_option_id', pg_temp.fx('vipd')));
  r := public.event_web_key_create(ev, 'live', 'Double live');
  insert into tx values ('hash:evd', encode(extensions.digest(r->>'key', 'sha256'), 'hex'));
  perform public.event_web_settings_save(ev, pg_temp.settings('live', pg_temp.tx('coded')) || jsonb_build_object('vip_option_id', pg_temp.fx('vipd')));
  insert into customers(full_name, phone, email) values ('Dora Doublevip', pg_temp.ph(400), pg_temp.mail('dv-dora')) returning id into c;
  insert into fx values ('c_dora', c);
  insert into customers(full_name, phone, email) values ('Cole Countervip', pg_temp.ph(401), pg_temp.mail('dv-cole')) returning id into c;
  insert into fx values ('c_cole', c);
end $$;
select pg_temp.put('dv_r1', pg_temp.call5('register', jsonb_build_object('registration', jsonb_build_object(
  'registration_id', pg_temp.bid('REG', 'dv1'), 'submitted_at', now(), 'referral_code', null, 'people', jsonb_build_array(
    pg_temp.person(1, 'Dora', 'Doublevip', pg_temp.ph(400), pg_temp.mail('dv-dora'), array[pg_temp.d(15)]),
    pg_temp.person(2, 'Cole', 'Countervip', pg_temp.ph(401), pg_temp.mail('dv-cole'), array[pg_temp.d(16)])))))::text);
select pg_temp.putx('dv_dora', pg_temp.pid(pg_temp.tx('dv_r1')::jsonb, 1));
select pg_temp.putx('dv_cole', pg_temp.pid(pg_temp.tx('dv_r1')::jsonb, 2));
select pg_temp.call5('vip_checkout', jsonb_build_object('order', jsonb_build_object(
  'order_id', pg_temp.bid('VIP', 'dv1'), 'upgrade_tokens', jsonb_build_array(pg_temp.tok(pg_temp.tx('dv_r1')::jsonb, 1), pg_temp.tok(pg_temp.tx('dv_r1')::jsonb, 2)),
  'payer', jsonb_build_object('name', 'Dora Doublevip', 'email', pg_temp.mail('dv-dora'), 'phone', null),
  'livemode', true, 'checkout_opened_at', now() - interval '3 minutes')));
select pg_temp.put('dv_p1', pg_temp.call5('vip_paid', jsonb_build_object('payment', jsonb_build_object(
  'order_id', pg_temp.bid('VIP', 'dv1'), 'provider', 'hitpay', 'payment_request_id', gen_random_uuid(), 'payment_id', gen_random_uuid(),
  'amount_cents', 14400, 'currency', 'SGD', 'livemode', true, 'paid_at', now() - interval '1 minute',
  'upgrade_tokens', jsonb_build_array(pg_temp.tok(pg_temp.tx('dv_r1')::jsonb, 1), pg_temp.tok(pg_temp.tx('dv_r1')::jsonb, 2)),
  'payer', jsonb_build_object('name', 'Dora Doublevip', 'email', pg_temp.mail('dv-dora'), 'phone', null))))::text);
-- Cole's second VIP: a ticket at the counter, its invoice not paid yet (waiting).
select pg_temp.putx('dv_counter', public.create_invoice_with_details(pg_temp.fx('van'), pg_temp.fx('c_cole'),
  jsonb_build_array(jsonb_build_object('kind', 'event_ticket', 'event_ticket_option_id', pg_temp.fx('vipd'), 'quantity', 1,
    'attendees', jsonb_build_array(jsonb_build_object('name', 'Cole Countervip', 'customer_id', pg_temp.fx('c_cole'))))),
  jsonb_build_object('business_date', public.sg_today())));
select pg_temp.put('dv_r2', pg_temp.call5('register', jsonb_build_object('registration', jsonb_build_object(
  'registration_id', pg_temp.bid('REG', 'dv2'), 'submitted_at', now(), 'referral_code', null, 'people', jsonb_build_array(
    pg_temp.person(1, 'Dee', 'Doublevip', pg_temp.ph(400), pg_temp.mail('dv-dee'), array[pg_temp.d(16)]),
    pg_temp.person(2, 'Kai', 'Elsewhere', pg_temp.ph(3), pg_temp.mail('dv-kai'), array[pg_temp.d(15)])))))::text);
select pg_temp.putx('dv_dee', pg_temp.pid(pg_temp.tx('dv_r2')::jsonb, 1));
select pg_temp.putx('dv_kai', pg_temp.pid(pg_temp.tx('dv_r2')::jsonb, 2));
select pg_temp.put('dv_t1', pg_temp.call5('vip_transfer', jsonb_build_object('order', jsonb_build_object(
  'order_id', pg_temp.bid('VIP', 'dv2'), 'upgrade_tokens', jsonb_build_array(pg_temp.tok(pg_temp.tx('dv_r2')::jsonb, 1)),
  'payer', jsonb_build_object('name', 'Dee Doublevip', 'email', pg_temp.mail('dv-dee'), 'phone', pg_temp.ph(400)),
  'method', 'paynow', 'reference', 'PN-DV2', 'paid_on', public.sg_today(), 'amount_cents', 7200, 'submitted_at', now())))::text);
-- Kai opens a HitPay checkout and does not pay: not a VIP payment.
select pg_temp.call5('vip_checkout', jsonb_build_object('order', jsonb_build_object(
  'order_id', pg_temp.bid('VIP', 'dv3'), 'upgrade_tokens', jsonb_build_array(pg_temp.tok(pg_temp.tx('dv_r2')::jsonb, 2)),
  'payer', jsonb_build_object('name', 'Kai Elsewhere', 'email', pg_temp.mail('dv-kai'), 'phone', null),
  'livemode', true, 'checkout_opened_at', now() - interval '3 minutes')));
select pg_temp.as_user('staff');
select pg_temp.put('dv_x1', public.event_web_guest_extras(pg_temp.fx('evd'))::text);
select pg_temp.put('dv_s1', public.event_planning_summary(pg_temp.fx('evd'))::text);
select pg_temp.check((pg_temp.tx('dv_p1')::jsonb)->>'status' = 'invoiced'
    and (pg_temp.pp(pg_temp.fx('dv_dee'))).match = 'held' and (pg_temp.pp(pg_temp.fx('dv_kai'))).match = 'held'
    and (pg_temp.tx('dv_t1')::jsonb)->>'status' = 'needs_review'
    and pg_temp.holds5(pg_temp.tx('dv_x1'))->'Dee Doublevip' @> '{"vip_payment": true, "vip_waiting": true}'::jsonb
    and pg_temp.cand5(pg_temp.tx('dv_x1'), 'Dee Doublevip', pg_temp.fx('c_dora'))->'guest'
        = jsonb_build_object('days', jsonb_build_array(pg_temp.d(15), pg_temp.d(16)),
                             'vips', jsonb_build_array(jsonb_build_object('state', 'paid', 'invoice_no', pg_temp.inv5(pg_temp.fx('dv_dora')))))
    and pg_temp.holds5(pg_temp.tx('dv_x1'))->'Kai Elsewhere' @> '{"vip_payment": false, "vip_waiting": true}'::jsonb
    and pg_temp.cand5(pg_temp.tx('dv_x1'), 'Kai Elsewhere', pg_temp.fx('c_phone')) ? 'guest'
    and pg_temp.cand5(pg_temp.tx('dv_x1'), 'Kai Elsewhere', pg_temp.fx('c_phone'))->'guest' = 'null'::jsonb,
  'DV1 To match: a candidate already a guest of this event shows their days and VIP paid with its invoice; one who is not a guest shows none; the held person''s own payment (a transfer waiting; a checkout opened and not paid is none)');
select pg_temp.check((pg_temp.tx('dv_x1')::jsonb)->'vip_doubles' = jsonb_build_array(jsonb_build_object(
        'customer_id', pg_temp.fx('c_cole'), 'full_name', 'Cole Countervip', 'vips', jsonb_build_array(
          jsonb_build_object('state', 'paid', 'invoice_no', pg_temp.inv5(pg_temp.fx('dv_cole'))),
          jsonb_build_object('state', 'waiting', 'invoice_no', (select invoice_no from invoices where id = pg_temp.fx('dv_counter'))))))
    and pg_temp.dbl5(pg_temp.tx('dv_x1'), (pg_temp.pp(pg_temp.fx('dv_cole'))).vip_guest_id)
    and pg_temp.dbl5(pg_temp.tx('dv_x1'), (select id from event_guests where invoice_id = pg_temp.fx('dv_counter')))
    and not pg_temp.dbl5(pg_temp.tx('dv_x1'), (pg_temp.pp(pg_temp.fx('dv_dora'))).vip_guest_id)
    and not pg_temp.dbl5(pg_temp.tx('dv_x1'), (pg_temp.pp(pg_temp.fx('dv_dee'))).free_guest_id)
    and (pg_temp.tx('dv_s1')::jsonb)->'vip' @> '{"count": 2, "waiting": 2}'::jsonb
    and (pg_temp.tx('dv_s1')::jsonb)->'vip'->'doubles' = jsonb_build_array(jsonb_build_object(
        'customer_id', pg_temp.fx('c_cole'), 'name', 'Cole Countervip', 'vips', jsonb_build_array(
          jsonb_build_object('state', 'paid', 'invoice_no', pg_temp.inv5(pg_temp.fx('dv_cole'))),
          jsonb_build_object('state', 'waiting', 'invoice_no', (select invoice_no from invoices where id = pg_temp.fx('dv_counter'))))))
    and (pg_temp.tx('dv_s1')::jsonb)->>'registered' = '4',
  'DV2 a customer with a website VIP paid and a counter VIP not paid yet holds two: their rows are flagged, vip_doubles and the Planning VIP block name them, counted once (2 VIPs; Dee''s transfer and Kai''s open checkout waiting apart): '
    || ((pg_temp.tx('dv_s1')::jsonb)->'vip')::text);
-- Staff link Dee to Dora (the page warned first): her transfer still waits for a Manager.
select pg_temp.put('dv_link', public.event_registration_attach(pg_temp.fx('dv_dee'), pg_temp.fx('c_dora'), 'Her daughter, same phone, asked at the counter')::text);
select pg_temp.put('dv_x2', public.event_web_guest_extras(pg_temp.fx('evd'))::text);
select pg_temp.put('dv_s2', public.event_planning_summary(pg_temp.fx('evd'))::text);
select pg_temp.check((pg_temp.pp(pg_temp.fx('dv_dee'))).customer_id = pg_temp.fx('c_dora')
    and (pg_temp.vorder('dv2')).status in ('recorded', 'needs_review')
    and (select jsonb_agg(d->>'full_name' order by d->>'full_name') from jsonb_array_elements((pg_temp.tx('dv_x2')::jsonb)->'vip_doubles') d)
        = '["Cole Countervip", "Dora Doublevip"]'::jsonb
    and (select d->'vips' from jsonb_array_elements((pg_temp.tx('dv_x2')::jsonb)->'vip_doubles') d where d->>'full_name' = 'Dora Doublevip')
        = jsonb_build_array(jsonb_build_object('state', 'paid', 'invoice_no', pg_temp.inv5(pg_temp.fx('dv_dora'))),
                            jsonb_build_object('state', 'waiting', 'invoice_no', null))
    and pg_temp.dbl5(pg_temp.tx('dv_x2'), (pg_temp.pp(pg_temp.fx('dv_dora'))).vip_guest_id)
    and pg_temp.dbl5(pg_temp.tx('dv_x2'), (pg_temp.pp(pg_temp.fx('dv_dora'))).free_guest_id)
    and pg_temp.dbl5(pg_temp.tx('dv_x2'), (pg_temp.pp(pg_temp.fx('dv_dee'))).free_guest_id)
    and not pg_temp.dbl5(pg_temp.tx('dv_x2'), (pg_temp.pp(pg_temp.fx('dv_kai'))).free_guest_id)
    and (pg_temp.tx('dv_s2')::jsonb)->'vip' @> '{"count": 2, "waiting": 1}'::jsonb
    and (select jsonb_agg(d->>'name' order by d->>'name') from jsonb_array_elements((pg_temp.tx('dv_s2')::jsonb)->'vip'->'doubles') d)
        = '["Cole Countervip", "Dora Doublevip"]'::jsonb
    and (pg_temp.tx('dv_s2')::jsonb)->>'registered' = '3'
    and (select jsonb_agg(jsonb_build_array(d->>'day', d->'registered') order by d->>'day') from jsonb_array_elements((pg_temp.tx('dv_s2')::jsonb)->'days') d)
        = jsonb_build_array(jsonb_build_array(pg_temp.d(15), 3), jsonb_build_array(pg_temp.d(16), 2)),
  'DV3 linked (allowed): Dora now holds two (paid, and Dee''s transfer waiting): all her rows flagged; the summary counts her once (3 guests; Day 2 two, not three; her transfer not counted apart, Kai''s open checkout is): '
    || ((pg_temp.tx('dv_s2')::jsonb)->'vip')::text);
-- Dee answers (her free record): Dora is still counted once, on her VIP record.
select pg_temp.call5('planning_answers', jsonb_build_object('planning', jsonb_build_object('submitted_at', now(), 'people', jsonb_build_array(
  pg_temp.pa(pg_temp.tok(pg_temp.tx('dv_r2')::jsonb, 1), 0, pg_temp.ans(jsonb_build_object('food', 'vegan')))))));
select pg_temp.as_user('manager');
select pg_temp.put('dv_conf', public.event_vip_order_invoice((pg_temp.vorder('dv2')).id)::text);
select pg_temp.as_user('staff');
select pg_temp.put('dv_x3', public.event_web_guest_extras(pg_temp.fx('evd'))::text);
select pg_temp.put('dv_s3', public.event_planning_summary(pg_temp.fx('evd'))::text);
select pg_temp.check((pg_temp.tx('dv_conf')::jsonb)->>'status' = 'invoiced'
    and (select d->'vips' from jsonb_array_elements((pg_temp.tx('dv_x3')::jsonb)->'vip_doubles') d where d->>'full_name' = 'Dora Doublevip')
        = jsonb_build_array(jsonb_build_object('state', 'paid', 'invoice_no', pg_temp.inv5(pg_temp.fx('dv_dora'))),
                            jsonb_build_object('state', 'paid', 'invoice_no', pg_temp.inv5(pg_temp.fx('dv_dee'))))
    and pg_temp.dbl5(pg_temp.tx('dv_x3'), (pg_temp.pp(pg_temp.fx('dv_dee'))).vip_guest_id)
    and (pg_temp.tx('dv_s3')::jsonb)->'vip' @> '{"count": 2, "waiting": 1, "answered": 1}'::jsonb
    and (pg_temp.tx('dv_s3')::jsonb)->'vip'->'food'->>'vegan' = '1'
    and (pg_temp.tx('dv_s3')::jsonb)->>'registered' = '3',
  'DV4 a Manager confirms Dee''s transfer: Dora holds two paid VIP invoices (both numbers), still counted once (2 VIPs; on the record with answers, Dee''s): '
    || ((pg_temp.tx('dv_s3')::jsonb)->'vip')::text);
-- The Owner cancels Dee's VIP invoice (one refunded): no longer two.
select pg_temp.as_user('owner');
select public.cancel_invoice_recorded((select i.id from pg_temp.vinvoices('dv2') i), 'Two VIP payments for one customer', gen_random_uuid());
select pg_temp.as_user('staff');
select pg_temp.put('dv_x4', public.event_web_guest_extras(pg_temp.fx('evd'))::text);
select pg_temp.put('dv_s4', public.event_planning_summary(pg_temp.fx('evd'))::text);
select pg_temp.check((select jsonb_agg(d->>'full_name') from jsonb_array_elements((pg_temp.tx('dv_x4')::jsonb)->'vip_doubles') d) = '["Cole Countervip"]'::jsonb
    and not pg_temp.dbl5(pg_temp.tx('dv_x4'), (pg_temp.pp(pg_temp.fx('dv_dora'))).vip_guest_id)
    and not pg_temp.dbl5(pg_temp.tx('dv_x4'), (pg_temp.pp(pg_temp.fx('dv_dee'))).free_guest_id)
    and (select jsonb_agg(d->>'name') from jsonb_array_elements((pg_temp.tx('dv_s4')::jsonb)->'vip'->'doubles') d) = '["Cole Countervip"]'::jsonb
    and (pg_temp.tx('dv_s4')::jsonb)->'vip' @> '{"count": 2}'::jsonb,
  'DV5 one of the two refunded (cancelled): Dora is flagged no more; Cole still is');
select pg_temp.check(not has_function_privilege('authenticated', 'public.event_vip_holders(uuid)', 'execute')
    and not has_function_privilege('anon', 'public.event_vip_holders(uuid)', 'execute')
    and has_function_privilege('service_role', 'public.event_vip_holders(uuid)', 'execute')
    and not exists (select 1 from public.event_vip_holders(pg_temp.fx('ev')) h where h.customer_id is null),
  'DV6 event_vip_holders is the server''s alone; it lists customers only');
-- The review of round 8 (21 Oct 2026): a dedicated event ev6 (two days). Cass holds a counter VIP, paid, with no
-- answers; Cleo is held on Cass's phone, sends a PayNow transfer and answers (halal, an allergy); Dot and Dottie are
-- held on Dan's phone, one for each day, and each sends a PayNow transfer. Staff link all three. The summary counts
-- Cass once, as a VIP, with Cleo's answers (allergy included), and Dan once on both days.
select pg_temp.as_user('owner');
create function pg_temp.call6(typ text, body jsonb) returns jsonb language sql as
$$ select pg_temp.call('eva', typ, jsonb_build_object('event', pg_temp.tx('codea')) || body) $$;
create function pg_temp.pn6(tag text, tok text, phone text) returns jsonb language sql as
$$ select pg_temp.call6('vip_transfer', jsonb_build_object('order', jsonb_build_object(
     'order_id', pg_temp.bid('VIP', tag), 'upgrade_tokens', jsonb_build_array(tok),
     'payer', jsonb_build_object('name', 'Payer ' || tag, 'email', pg_temp.mail('payer-' || tag), 'phone', phone),
     'method', 'paynow', 'reference', 'PN-' || tag, 'paid_on', public.sg_today(), 'amount_cents', 7200, 'submitted_at', now()))) $$;
do $$ declare ev uuid; r jsonb; c uuid; v uuid; begin
  ev := public.event_save(jsonb_build_object('name', 'HT436 Double VIP answers ' || pg_temp.tx('sfx'), 'daily_start', '09:00', 'daily_end', '19:00',
    'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(25)), jsonb_build_object('day', pg_temp.d(26))),
    'store_ids', jsonb_build_array(pg_temp.fx('van')),
    'options', jsonb_build_array(jsonb_build_object('name', 'VIP', 'days_count', 2, 'price', 72))));
  insert into fx values ('eva', ev), ('vipa', (select id from public.event_ticket_options where event_id = ev));
  insert into tx values ('codea', 'HT436A-' || pg_temp.tx('sfx'));
  perform public.event_web_settings_save(ev, pg_temp.settings('off', pg_temp.tx('codea')) || jsonb_build_object('vip_option_id', pg_temp.fx('vipa')));
  r := public.event_web_key_create(ev, 'live', 'Answers live');
  insert into tx values ('hash:eva', encode(extensions.digest(r->>'key', 'sha256'), 'hex'));
  perform public.event_web_settings_save(ev, pg_temp.settings('live', pg_temp.tx('codea')) || jsonb_build_object('vip_option_id', pg_temp.fx('vipa')));
  insert into customers(full_name, phone, email) values ('Cass Countervip', pg_temp.ph(430), pg_temp.mail('dv-cass')) returning id into c;
  insert into fx values ('c_cass', c);
  insert into customers(full_name, phone, email) values ('Dan Twotransfers', pg_temp.ph(431), pg_temp.mail('dv-dan')) returning id into c;
  insert into fx values ('c_dan', c);
  -- Cass's VIP at the counter, paid.
  v := public.create_invoice_with_details(pg_temp.fx('van'), pg_temp.fx('c_cass'),
    jsonb_build_array(jsonb_build_object('kind', 'event_ticket', 'event_ticket_option_id', pg_temp.fx('vipa'), 'quantity', 1,
      'attendees', jsonb_build_array(jsonb_build_object('name', 'Cass Countervip', 'customer_id', pg_temp.fx('c_cass'))))),
    jsonb_build_object('business_date', public.sg_today()));
  perform public.record_invoice_payment(v, jsonb_build_array(jsonb_build_object('payment_method_id', pg_temp.fx('bank'),
    'amount', (select total_amount from invoices where id = v), 'reference', 'Counter VIP', 'payment_date', public.sg_today())), gen_random_uuid());
  insert into fx values ('dv_cass_inv', v);
end $$;
select pg_temp.put('dv_r6', pg_temp.call6('register', jsonb_build_object('registration', jsonb_build_object(
  'registration_id', pg_temp.bid('REG', 'dv6'), 'submitted_at', now(), 'referral_code', null, 'people', jsonb_build_array(
    pg_temp.person(1, 'Cleo', 'Heldtransfer', pg_temp.ph(430), pg_temp.mail('dv-cleo'), array[pg_temp.d(25)]),
    pg_temp.person(2, 'Dot', 'Heldone', pg_temp.ph(431), pg_temp.mail('dv-dot'), array[pg_temp.d(25)]),
    pg_temp.person(3, 'Dottie', 'Heldtwo', pg_temp.ph(431), pg_temp.mail('dv-dottie'), array[pg_temp.d(26)])))))::text);
select pg_temp.putx('dv_cleo', pg_temp.pid(pg_temp.tx('dv_r6')::jsonb, 1));
select pg_temp.putx('dv_dot', pg_temp.pid(pg_temp.tx('dv_r6')::jsonb, 2));
select pg_temp.putx('dv_dottie', pg_temp.pid(pg_temp.tx('dv_r6')::jsonb, 3));
select pg_temp.put('dv_t6c', pg_temp.pn6('dv6c', pg_temp.tok(pg_temp.tx('dv_r6')::jsonb, 1), pg_temp.ph(430))::text);
select pg_temp.put('dv_t6d', pg_temp.pn6('dv6d', pg_temp.tok(pg_temp.tx('dv_r6')::jsonb, 2), pg_temp.ph(431))::text);
select pg_temp.put('dv_t6e', pg_temp.pn6('dv6e', pg_temp.tok(pg_temp.tx('dv_r6')::jsonb, 3), pg_temp.ph(431))::text);
select pg_temp.call6('planning_answers', jsonb_build_object('planning', jsonb_build_object('submitted_at', now(), 'people', jsonb_build_array(
  pg_temp.pa(pg_temp.tok(pg_temp.tx('dv_r6')::jsonb, 1), 0,
    pg_temp.ans(jsonb_build_object('food', 'halal', 'allergy', 'yes', 'allergy_details', 'DV7 peanuts')))))));
select pg_temp.as_user('staff');
select public.event_registration_attach(pg_temp.fx('dv_cleo'), pg_temp.fx('c_cass'), 'Her daughter, same phone, asked at the counter');
select public.event_registration_attach(pg_temp.fx('dv_dot'), pg_temp.fx('c_dan'), 'The same person, asked him');
select public.event_registration_attach(pg_temp.fx('dv_dottie'), pg_temp.fx('c_dan'), 'The same person, asked him');
select pg_temp.put('dv_x6', public.event_web_guest_extras(pg_temp.fx('eva'))::text);
select pg_temp.put('dv_s6', public.event_planning_summary(pg_temp.fx('eva'))::text);
select pg_temp.check((pg_temp.tx('dv_t6c')::jsonb)->>'status' = 'needs_review'
    and (pg_temp.pp(pg_temp.fx('dv_cleo'))).customer_id = pg_temp.fx('c_cass')
    and (select jsonb_agg(d->>'full_name' order by d->>'full_name') from jsonb_array_elements((pg_temp.tx('dv_x6')::jsonb)->'vip_doubles') d)
        = '["Cass Countervip", "Dan Twotransfers"]'::jsonb
    and (pg_temp.tx('dv_s6')::jsonb)->>'registered' = '2' and (pg_temp.tx('dv_s6')::jsonb)->>'answered' = '1'
    and (pg_temp.tx('dv_s6')::jsonb)->'vip' @> '{"count": 1, "answered": 1, "waiting": 1}'::jsonb
    and (pg_temp.tx('dv_s6')::jsonb)->'vip'->'food' @> '{"halal": 1, "not_said": 0}'::jsonb
    and (pg_temp.tx('dv_s6')::jsonb)->'vip'->'allergies' = jsonb_build_array(jsonb_build_object(
          'guest_id', (select id from event_guests where invoice_id = pg_temp.fx('dv_cass_inv')), 'name', 'Cass Countervip',
          'text', 'DV7 peanuts', 'vip', true))
    and (pg_temp.tx('dv_s6')::jsonb)->'days'->0 @> '{"registered": 2, "answered": 1}'::jsonb
    and (pg_temp.tx('dv_s6')::jsonb)->'days'->0->'food' @> '{"halal": 1}'::jsonb
    and ((pg_temp.tx('dv_s6')::jsonb)->'days'->0->'allergies')::text like '%DV7 peanuts%'
    and ((pg_temp.tx('dv_s6')::jsonb)->'days'->1->'allergies')::text like '%DV7 peanuts%',
  'DV7 a counter VIP paid with no answers, linked to a held person whose transfer waits and who answered (halal, an allergy): counted once as a VIP, with her answers in the VIP block and on each day: '
    || (pg_temp.tx('dv_s6')::jsonb)::text);
select pg_temp.check((select jsonb_agg(jsonb_build_array(d->>'day', d->'registered') order by d->>'day') from jsonb_array_elements((pg_temp.tx('dv_s6')::jsonb)->'days') d)
        = jsonb_build_array(jsonb_build_array(pg_temp.d(25), 2), jsonb_build_array(pg_temp.d(26), 2))
    and (select count(*) from public.event_vip_holders(pg_temp.fx('eva')) h where h.customer_id = pg_temp.fx('c_dan') and h.state = 'waiting') = 2,
  'DV8 two transfers waiting on two free records of one customer (Day 1 and Day 2): counted once, on both days (each day''s registered counts them)');

-- ═════ D Guards ═════
select pg_temp.as_user('owner');
-- event_delete refuses this event for its ticket invoices first; the guard is
-- a trigger, so every path that deletes an event meets it.
select pg_temp.put('d1', pg_temp.err(format('update public.events set deleted_at = now() where id = %L', pg_temp.fx('ev'))));
update event_web_settings set mode = 'off' where event_id = pg_temp.fx('ev');
select pg_temp.put('d1b', pg_temp.err(format('update public.events set deleted_at = now() where id = %L', pg_temp.fx('ev'))));
update event_web_settings set mode = 'live' where event_id = pg_temp.fx('ev');
select pg_temp.check(pg_temp.tx('d1') like 'The website still takes registrations for "HT436 Health Seminar %". Switch it Off on the Website tab, then delete the event.'
    and pg_temp.tx('d1b') like 'The website of "HT436 Health Seminar %" has % VIP payment(s) waiting. Create their invoices, or close them as refunded, first.',
  'D1 the event is not deleted while its website is on, or while VIP money waits: ' || pg_temp.tx('d1b'));
select pg_temp.as_user('owner');
select public.merge_customer_records(pg_temp.fx('c_exact'), pg_temp.fx('fern'), 'The same person', gen_random_uuid());
select pg_temp.check((pg_temp.f1(1)).customer_id = pg_temp.fx('c_exact')
    and (pg_temp.guest((pg_temp.f1(1)).free_guest_id)).customer_id = pg_temp.fx('c_exact'),
  'D2 a merge moves the registered person and their guest record to the customer kept');
-- D3 a deleted event's keys are revoked with it, and a key of a deleted event answers bad_key.
select pg_temp.as_user('owner');
do $$ declare ev uuid; r jsonb; begin
  perform pg_temp.as_user('owner');
  ev := public.event_save(jsonb_build_object('name', 'HT436 Deleted ' || pg_temp.tx('sfx'),
    'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(10))), 'store_ids', jsonb_build_array(pg_temp.fx('van')),
    'options', jsonb_build_array(jsonb_build_object('name', 'VIP', 'days_count', 1, 'price', 72))));
  insert into fx values ('ev3', ev);
  insert into tx values ('code3', 'HT436D-' || pg_temp.tx('sfx'));
  perform public.event_web_settings_save(ev, pg_temp.settings('off', pg_temp.tx('code3'))
    || jsonb_build_object('vip_option_id', (select id from public.event_ticket_options where event_id = ev)));
  r := public.event_web_key_create(ev, 'live', 'Deleted event key');
  insert into tx values ('hash:ev3', encode(extensions.digest(r->>'key', 'sha256'), 'hex'));
  insert into fx values ('key_ev3', (r->>'key_id')::uuid);
  r := public.event_web_key_create(ev, 'test', 'Deleted event test key');
  perform public.event_web_settings_save(ev, pg_temp.settings('record_only', pg_temp.tx('code3'))
    || jsonb_build_object('vip_option_id', (select id from public.event_ticket_options where event_id = ev)));
end $$;
select pg_temp.put('d3_reg', pg_temp.call('ev3', 'register', jsonb_build_object('event', pg_temp.tx('code3'), 'registration', jsonb_build_object(
  'registration_id', pg_temp.bid('REG', 'd3'), 'submitted_at', now(), 'referral_code', null,
  'people', jsonb_build_array(pg_temp.person(1, 'Dora', 'Deleted', pg_temp.ph(45), pg_temp.mail('dora'), array[pg_temp.d(10)])))))::text);
update event_web_settings set mode = 'off' where event_id = pg_temp.fx('ev3');
select pg_temp.put('d3_sync_before', pg_temp.call('ev3', 'sync', jsonb_build_object('event', pg_temp.tx('code3')))::text);
select pg_temp.put('d3_delete', pg_temp.err(format('select public.event_delete(%L, %L)', pg_temp.fx('ev3'), 'Set up by mistake')));
select pg_temp.put('d3_sync', pg_temp.call('ev3', 'sync', jsonb_build_object('event', pg_temp.tx('code3')))::text);
select pg_temp.put('d3_person', pg_temp.call('ev3', 'person', jsonb_build_object('event', pg_temp.tx('code3'),
  'upgrade_token', pg_temp.tok(pg_temp.tx('d3_reg')::jsonb, 1)))::text);
-- Even a key left unrevoked (by a path that skipped the trigger) answers nothing once its event is deleted.
update public.event_web_keys set revoked_at = null, revoked_by = null, revoked_reason = null where id = pg_temp.fx('key_ev3');
select pg_temp.put('d3_unrevoked', pg_temp.call('ev3', 'sync', jsonb_build_object('event', pg_temp.tx('code3')))::text);
select pg_temp.check((pg_temp.tx('d3_reg')::jsonb)->>'status' = 'registered' and (pg_temp.tx('d3_sync_before')::jsonb)->>'status' = 'ok'
    and pg_temp.tx('d3_delete') = 'ok'
    and pg_temp.tx('d3_sync')::jsonb = '{"ok": false, "error": "bad_key"}'::jsonb
    and pg_temp.tx('d3_person')::jsonb = '{"ok": false, "error": "bad_key"}'::jsonb
    and pg_temp.tx('d3_unrevoked')::jsonb = '{"ok": false, "error": "bad_key"}'::jsonb
    and (select count(*) from public.audit_logs a join public.event_web_keys k on k.id = a.record_id
          where k.event_id = pg_temp.fx('ev3') and a.action = 'event_web_key_revoked' and a.reason = 'Event deleted'
            and a.changed_by = pg_temp.fx('owner')) = 2
    and (select count(*) from public.event_web_keys where event_id = pg_temp.fx('ev3') and revoked_reason = 'Event deleted') = 1,
  'D3 deleting the event revokes its live and test keys (audited); sync and person then answer bad_key, even for a key left unrevoked');

-- ═════ P Grants ═════
select pg_temp.check(not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
                                   and (p.proname like 'event\_web\_%' or p.proname like 'event\_vip\_%' or p.proname like 'event\_registration\_%'
                                        or p.proname like 'event\_planning\_%'
                                        or p.proname in ('trg_event_vip_guest_follow', 'trg_event_vip_parked_guest', 'trg_event_web_delete_guard',
                                                         'trg_event_vip_refund_vouchers', 'trg_event_web_referral_check_decided',
                                                         'trg_event_vip_used_later_reason'))
                                   and has_function_privilege('anon', p.oid, 'execute')),
  'P1 nothing of 436 is callable signed out');
select pg_temp.check(not has_function_privilege('authenticated', 'public.trg_event_web_referral_check_decided()', 'execute')
    and not has_function_privilege('authenticated', 'public.event_web_affiliate_contact(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.event_web_referral_note(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.trg_event_vip_used_later_reason()', 'execute')
    and (select count(*) from pg_trigger t where t.tgrelid = 'public.referral_signup_checks'::regclass and not t.tgisinternal
           and t.tgfoid = 'public.trg_event_web_referral_check_decided()'::regprocedure) = 1
    and (select count(*) from pg_trigger t where t.tgrelid = 'public.approval_requests'::regclass and not t.tgisinternal
           and t.tgfoid = 'public.trg_event_vip_used_later_reason()'::regprocedure) = 1,
  'P5 the check-decision trigger is on referral_signup_checks once, the override-reason trigger on approval_requests once; their functions and the new helpers are the server''s');
select pg_temp.check((select array_agg(p.oid::regprocedure::text order by p.oid::regprocedure::text) from pg_proc p where p.pronamespace = 'public'::regnamespace
                        and (p.proname like 'event\_web\_%' or p.proname like 'event\_vip\_%' or p.proname like 'event\_registration\_%'
                             or p.proname like 'event\_planning\_%')
                        and has_function_privilege('authenticated', p.oid, 'execute'))
                     = array['event_planning_list(uuid)', 'event_planning_save(uuid,jsonb,integer,text)', 'event_planning_summary(uuid)',
                             'event_registration_attach(uuid,uuid,text)', 'event_registration_close(uuid,text)',
                             'event_registration_create_customer(uuid,text)', 'event_vip_gift_give(uuid,uuid,date,uuid)',
                             'event_vip_gift_undo(uuid,text)', 'event_vip_order_close_refunded(uuid,text,boolean)',
                             'event_vip_order_dismiss(uuid,text,boolean)', 'event_vip_order_invoice(uuid,integer)', 'event_vip_orders_list(uuid)',
                             'event_web_guest_extras(uuid)', 'event_web_key_create(uuid,text,text)', 'event_web_key_revoke(uuid,text)',
                             'event_web_set_talks(uuid,jsonb)', 'event_web_set_venue(uuid,text)', 'event_web_settings_get(uuid)',
                             'event_web_settings_save(uuid,jsonb)', 'event_web_test_clear(uuid)'],
  'P2 signed-in staff reach the page''s 20 functions only (each checks the caller); the website''s and the rules are the server''s');
select pg_temp.check(not exists (select 1 from unnest(array['event_web_settings', 'event_web_keys', 'event_web_requests', 'event_registrations',
                                   'event_registration_people', 'event_vip_orders', 'event_vip_order_people', 'event_vip_gifts',
                                   'event_planning_answers']) t
                                  where has_table_privilege('anon', 'public.' || t, 'select,insert,update,delete')
                                     or has_table_privilege('authenticated', 'public.' || t, 'select,insert,update,delete')
                                     or not (select relrowsecurity from pg_class where oid = ('public.' || t)::regclass)
                                     or not has_table_privilege('service_role', 'public.' || t, 'select')),
  'P3 the nine tables are no client''s (row level security on, no grant), and the server''s');
select pg_temp.check(has_function_privilege('service_role', 'public.event_web_call(text,uuid,text,jsonb)', 'execute')
    and not has_function_privilege('authenticated', 'public.event_web_call(text,uuid,text,jsonb)', 'execute')
    and not has_function_privilege('authenticated', 'public.event_ticket_line_check(jsonb,date,uuid,integer)', 'execute'),
  'P4 the dispatcher is the service role''s alone; the patched ticket check keeps its grants');
select pg_temp.as_user('owner');
select pg_temp.put('tclear', public.event_web_test_clear(pg_temp.fx('ev'))::text);
select pg_temp.check((pg_temp.tx('tclear')::jsonb) @> '{"orders": 2}'::jsonb
    and not exists (select 1 from event_registrations where event_id = pg_temp.fx('ev') and is_test
                      and registration_id <> pg_temp.bid('REG', 't1'))
    and exists (select 1 from event_vip_orders where event_id = pg_temp.fx('ev') and is_test and livemode),
  'S8 Clear test data: the test rows go, except a real payment that reached the test key (and its people): ' || pg_temp.tx('tclear'));

-- ═════ M 436 twice ═════
\if :{?skip_install}
\else
select pg_temp.check(not exists (select 1 from m436 m
                                   left join pg_proc p on p.oid::regprocedure::text = m.fn and p.pronamespace = 'public'::regnamespace
                                  where p.oid is null or md5(pg_get_functiondef(p.oid)) <> m.md5)
    and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f') = (select count(*) from m436),
  'M running 436 a second time changed no function');
\endif

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All event-website checks passed.';
end $$;
rollback;
