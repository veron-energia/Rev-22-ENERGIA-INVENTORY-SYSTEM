-- Website orders become invoices (372, with 373's hardening and 376's HitPay orders).
--
--   O1 A record-only channel keeps the order and makes no invoice; asked again,
--      it says the same.
--   O2 A live channel makes the invoice at payment: the event's store, raised
--      by the channel's profile, dated on the Singapore day the checkout was
--      opened, one ticket line with the buyer and placeholders, the total
--      equal to Stripe's, the payment recorded with the channel's method and
--      the Stripe payment as reference; the invoice is paid and its people are
--      on the guest list. A new buyer is a new customer with the channel's
--      source.
--   O3 Nothing twice: the same checkout again returns the same invoice (no
--      second invoice, payment or customer).
--   O4 A checkout opened on the last early-bird day and paid after midnight
--      keeps the early-bird price and is dated on the day it was opened.
--   O5 A total that does not match Stripe's leaves nothing behind and waits
--      for review, with the reason.
--   O6 Phone alone decides the customer: one customer with that phone is the
--      buyer (whatever the name); two or more, and the order waits with them as
--      candidates; a Manager then chooses one, or a new customer.
--   O7 Test payments are refused unless the channel allows them; an off
--      channel refuses; a malformed or mismatched checkout is refused and not
--      kept.
--   O8 The buyer's names rename the people on the invoice (same guests,
--      audited) and give a customer this order made its name parts; names for
--      the wrong number of people are not used; names before the invoice are
--      used when it is made.
--   O9 Who may do what: only the service role hands orders in; Owners, Admins
--      and Managers (of the store) see and resolve; only an Owner switches.
--   O10 What the review of 372 found: phones stored in the old local form,
--      test payments recorded while allowed, names sent again after staff
--      corrected the customer, and the audit of naming a customer.
--   O12 HitPay (376): a HitPay order is kept as one, invoiced once and paid
--      with the channel's HitPay method ("HitPay (online)" unless the channel
--      names another), with HitPay's payment id as reference; its notes and
--      reasons name HitPay; a sandbox payment is refused like a Stripe test
--      payment; malformed ids and unknown providers are refused and not kept;
--      a Manager resolves a HitPay time reason; names go on its invoice; the
--      list says each order's provider.
--   O11 What the pre-apply review of 372 found (373):
--      - a customer made in advance under a guessable request id is not used;
--        a buyer who named themselves first gets those name parts;
--      - times that do not hang together wait for review, checked before
--        anything else, at their limits, and also when names invoice an old
--        recorded order. Only a Manager who has seen a time reason skips
--        them. An invoice is never dated after today;
--      - new names keep what staff set on a guest, and go on the line the
--        order made;
--      - names the order already had change nothing;
--      - names that do not fit are kept with the reason, and go on once they
--        fit: sent again, or put on by a Manager.
--
-- Every check runs, then the file fails if any did. Disposable database only;
-- everything is rolled back. Fixtures carry a random suffix.
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
-- A Singapore wall-clock moment on day n, but never later than now (the
-- moment the order arrives): times after that wait for review (373), and
-- these fixtures run at any time of day.
create function pg_temp.sg(n int, hhmm text) returns timestamptz language sql as
$$ select least(((public.sg_today() + n)::text || ' ' || hhmm)::timestamp at time zone 'Asia/Singapore', now()) $$;
create function pg_temp.phone() returns text language sql volatile as $$
  select '+659123' || lpad(n::text, 4, '0') from generate_series(0, 9999) n
   where not exists (select 1 from public.customers c
                      where regexp_replace(coalesce(c.phone, ''), '\D', '', 'g') = '659123' || lpad(n::text, 4, '0'))
   order by random() limit 1
$$;
-- One paid order as the edge function hands it in.
create function pg_temp.paid(sess text, ticket text, qty int, unit_cents int, buyer text, phone text,
  opened timestamptz, paid timestamptz, early boolean default false, total_cents int default null) returns jsonb language sql as
$$ select jsonb_build_object('channel', pg_temp.tx('channel'), 'stripe_session_id', sess,
     'stripe_payment_intent', 'pi_' || substr(md5(sess), 1, 24), 'livemode', sess like 'cs_live_%',
     'ticket', ticket, 'quantity', qty, 'unit_amount_cents', unit_cents,
     'amount_total_cents', coalesce(total_cents, unit_cents * qty), 'early_bird', early,
     'buyer', jsonb_build_object('name', buyer, 'email', 'buyer-' || substr(md5(sess), 1, 6) || '@tests.invalid', 'phone', phone),
     'checkout_opened_at', opened, 'paid_at', paid) $$;
-- A Monday pass for one, checkout opened at a given moment: the early bird
-- (until yesterday) halves it.
create function pg_temp.day1(sess text, buyer text, phone text, opened timestamptz, paid timestamptz) returns jsonb language sql as
$$ select pg_temp.paid(sess, 'day1', 1,
     case when (opened at time zone 'Asia/Singapore')::date <= pg_temp.d(-1) then 3050 else 6100 end, buyer, phone, opened, paid,
     (opened at time zone 'Asia/Singapore')::date <= pg_temp.d(-1)) $$;
create function pg_temp.sess(tag text) returns text language sql as
$$ select 'cs_live_O372' || tag || pg_temp.tx('sfx') $$;
create function pg_temp.order_of(sess text) returns public.web_orders language sql as
$$ select * from public.web_orders where stripe_session_id = sess $$;

-- ═════ Fixtures ═════
do $$
declare sfx text := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  u uuid; k text; st uuid; st2 uuid; ev uuid; o1 uuid; o2 uuid; src uuid; pm uuid;
begin
  insert into tx values ('sfx', sfx), ('channel', 'o372-' || lower(sfx));
  foreach k in array array['owner','acting','manager','manager2','staff'] loop
    u := gen_random_uuid();
    insert into auth.users(id, email) values (u, 'o372-' || k || '-' || lower(sfx) || '@tests.invalid');
    insert into profiles(id, full_name, email, role)
    values (u, 'O372 ' || k, 'o372-' || k || '-' || lower(sfx) || '@tests.invalid',
            case k when 'staff' then 'staff' when 'manager' then 'manager' when 'manager2' then 'manager' else 'owner' end::user_role);
    insert into fx values (k, u);
  end loop;
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  insert into stores(name, code, country_code) values ('O372 Van ' || sfx, 'O372V' || sfx, 'SG') returning id into st;
  insert into stores(name, code, country_code) values ('O372 Shop ' || sfx, 'O372S' || sfx, 'SG') returning id into st2;
  insert into fx values ('van', st), ('shop', st2);
  insert into user_store_assignments(user_id, store_id) values
    (pg_temp.fx('manager'), st), (pg_temp.fx('staff'), st), (pg_temp.fx('manager2'), st2);
  -- Early bird ends yesterday; the event is in a week.
  ev := public.event_save(jsonb_build_object('name', 'O372 Birthday ' || sfx,
    'early_bird_until', pg_temp.d(-1), 'early_bird_percent', 50,
    'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(7)), jsonb_build_object('day', pg_temp.d(8))),
    'store_ids', jsonb_build_array(st),
    'options', jsonb_build_array(jsonb_build_object('name', '1 Day', 'days_count', 1, 'price', 61),
                                 jsonb_build_object('name', '2 Days', 'days_count', 2, 'price', 94))));
  select id into o1 from public.event_ticket_options where event_id = ev and name = '1 Day';
  select id into o2 from public.event_ticket_options where event_id = ev and name = '2 Days';
  insert into fx values ('ev', ev), ('one', o1), ('two', o2);
  insert into customer_source_options(label, is_active, requires_details, sort_order)
  values ('O372 Event ' || sfx, true, true, 9999) returning id into src;
  insert into fx values ('src', src);
  select id into pm from public.payment_methods where name = 'Stripe (online)';
  insert into fx values ('stripe', pm);
  insert into public.web_order_channels (key, event_id, ticket_map, store_id, acting_profile_id, payment_method_id,
                                         source_option_id, source_details, mode)
  values (pg_temp.tx('channel'), ev, jsonb_build_object(
            'both', jsonb_build_object('option_id', o2, 'days', jsonb_build_array(pg_temp.d(7), pg_temp.d(8))),
            'day1', jsonb_build_object('option_id', o1, 'days', jsonb_build_array(pg_temp.d(7))),
            'day2', jsonb_build_object('option_id', o1, 'days', jsonb_build_array(pg_temp.d(8)))),
          st, pg_temp.fx('acting'), pm, src, 'O372 Birthday (website)', 'record_only');
end $$;
select pg_temp.check(pg_temp.fx('stripe') is not null, 'O0 the migration adds the "Stripe (online)" payment method');

-- ═════ O1 Record only ═════
select pg_temp.as_service();
do $$ declare r jsonb; begin
  insert into tx values ('ph_a', pg_temp.phone());
  r := public.web_order_paid(pg_temp.paid(pg_temp.sess('A'), 'both', 2, 9400, 'Buyer A', pg_temp.tx('ph_a'),
         pg_temp.sg(0, '10:00'), pg_temp.sg(0, '10:05')));
  insert into tx values ('o1_status', r->>'status');
  r := public.web_order_paid(pg_temp.paid(pg_temp.sess('A'), 'both', 2, 9400, 'Buyer A', pg_temp.tx('ph_a'),
         pg_temp.sg(0, '10:00'), pg_temp.sg(0, '10:05')));
  insert into tx values ('o1_again', r->>'status');
end $$;
select pg_temp.check(pg_temp.tx('o1_status') = 'recorded' and pg_temp.tx('o1_again') = 'recorded'
    and (select invoice_id is null from pg_temp.order_of(pg_temp.sess('A')))
    and (select count(*) from public.web_orders where stripe_session_id = pg_temp.sess('A')) = 1,
  'O1 a record-only channel keeps the order once and makes no invoice');

-- ═════ O2 Live ═════
update public.web_order_channels set mode = 'live' where key = pg_temp.tx('channel');
select pg_temp.as_service();
do $$ declare r jsonb; begin
  insert into tx values ('ph_b', pg_temp.phone());
  r := public.web_order_paid(pg_temp.paid(pg_temp.sess('B'), 'day1', 2, 6100, 'Buyer Bee', pg_temp.tx('ph_b'),
         pg_temp.sg(0, '09:00'), pg_temp.sg(0, '09:10')));
  insert into tx values ('o2_status', r->>'status'), ('o2_no', r->>'invoice_no');
end $$;
select pg_temp.check(pg_temp.tx('o2_status') = 'invoiced' and pg_temp.tx('o2_no') like 'INV-%',
  'O2 a live channel makes the invoice at payment and returns its number');
select pg_temp.check((select (i.store_id, i.created_by, i.business_date, i.total_amount, i.status)
                             = (pg_temp.fx('van'), pg_temp.fx('acting'), pg_temp.d(0), 122.00::numeric, 'paid'::invoice_status)
                        from public.invoices i where i.invoice_no = pg_temp.tx('o2_no')),
  'O2 the invoice is the event store''s, raised by the channel''s profile, dated today, S$122.00 and paid');
select pg_temp.check((select (ii.line_kind::text, ii.quantity, ii.unit_price, ii.event_days) = ('event_ticket', 2, 61.00::numeric, array[pg_temp.d(7)])
                        from public.invoice_items ii join public.invoices i on i.id = ii.invoice_id where i.invoice_no = pg_temp.tx('o2_no')),
  'O2 one ticket line: the Monday 1-day pass for two, full price');
select pg_temp.check((select string_agg(g.name, ' | ' order by g.line_position) from public.event_guests g
                        join public.invoices i on i.id = g.invoice_id where i.invoice_no = pg_temp.tx('o2_no') and g.status = 'registered')
                       = 'Buyer Bee | Buyer Bee · Guest 2',
  'O2 the buyer and a placeholder are on the guest list');
select pg_temp.check((select (p.payment_method_id, p.amount, p.payment_reference) = (pg_temp.fx('stripe'), 122.00::numeric, 'pi_' || substr(md5(pg_temp.sess('B')), 1, 24))
                        from public.invoice_payments p join public.invoices i on i.id = p.invoice_id where i.invoice_no = pg_temp.tx('o2_no')),
  'O2 the payment is Stripe (online), for what Stripe charged, with the Stripe payment as reference');
select pg_temp.check((select (c.phone, c.full_name, c.source_option_id, c.source_details)
                             = (pg_temp.tx('ph_b'), 'Buyer Bee', pg_temp.fx('src'), 'O372 Birthday (website)')
                        from public.customers c join public.invoices i on i.customer_id = c.id where i.invoice_no = pg_temp.tx('o2_no'))
    and (select customer_created from pg_temp.order_of(pg_temp.sess('B'))),
  'O2 a new buyer is a new customer with the channel''s source');

-- ═════ O3 Nothing twice ═════
select pg_temp.as_service();
do $$ declare r jsonb; begin
  r := public.web_order_paid(pg_temp.paid(pg_temp.sess('B'), 'day1', 2, 6100, 'Buyer Bee', pg_temp.tx('ph_b'),
         pg_temp.sg(0, '09:00'), pg_temp.sg(0, '09:10')));
  insert into tx values ('o3_no', r->>'invoice_no');
end $$;
select pg_temp.check(pg_temp.tx('o3_no') = pg_temp.tx('o2_no')
    and (select count(*) from public.invoices where notes like '%' || pg_temp.sess('B') || '%') = 1
    and (select count(*) from public.invoice_payments p join public.invoices i on i.id = p.invoice_id where i.invoice_no = pg_temp.tx('o2_no')) = 1
    and (select count(*) from public.customers where phone = pg_temp.tx('ph_b')) = 1,
  'O3 the same checkout again returns the same invoice: no second invoice, payment or customer');

-- ═════ O4 Early bird across midnight ═════
select pg_temp.as_service();
do $$ declare r jsonb; begin
  insert into tx values ('ph_c', pg_temp.phone());
  -- Opened 23:40 on the last early-bird day (yesterday), paid 00:20 today.
  r := public.web_order_paid(pg_temp.paid(pg_temp.sess('C'), 'both', 1, 4700, 'Buyer Cee', pg_temp.tx('ph_c'),
         pg_temp.sg(-1, '23:40'), pg_temp.sg(0, '00:20'), true));
  insert into tx values ('o4_status', r->>'status'), ('o4_no', r->>'invoice_no');
end $$;
select pg_temp.check(pg_temp.tx('o4_status') = 'invoiced'
    and (select (i.business_date, i.total_amount) = (pg_temp.d(-1), 47.00::numeric) from public.invoices i where i.invoice_no = pg_temp.tx('o4_no')),
  'O4 a checkout opened on the last early-bird day and paid after midnight keeps S$47.00, dated the day it was opened');

-- ═════ O5 Totals must agree ═════
select pg_temp.as_service();
do $$ declare r jsonb; begin
  insert into tx values ('ph_d', pg_temp.phone());
  -- Early-bird money for a checkout opened today (the early bird has ended).
  r := public.web_order_paid(pg_temp.paid(pg_temp.sess('D'), 'both', 1, 4700, 'Buyer Dee', pg_temp.tx('ph_d'),
         pg_temp.sg(0, '11:00'), pg_temp.sg(0, '11:01'), true));
  insert into tx values ('o5_status', r->>'status'), ('o5_reason', r->>'review_reason');
end $$;
select pg_temp.check(pg_temp.tx('o5_status') = 'needs_review' and pg_temp.tx('o5_reason') like '%S$94.00%S$47.00%'
    and not exists (select 1 from public.invoices where notes like '%' || pg_temp.sess('D') || '%')
    and not exists (select 1 from public.customers where phone = pg_temp.tx('ph_d')),
  'O5 a total that differs from Stripe''s leaves no invoice or customer behind and waits for review');

-- ═════ O6 Phone alone decides the customer ═════
select pg_temp.as_user('owner');
do $$ declare c uuid; begin
  insert into tx values ('ph_e', pg_temp.phone()), ('ph_f', pg_temp.phone());
  insert into customers(full_name, phone) values ('Existing Person', pg_temp.tx('ph_e')) returning id into c;
  insert into fx values ('cust_e', c);
  insert into customers(full_name, phone) values ('Twin One', pg_temp.tx('ph_f')) returning id into c;
  insert into fx values ('twin1', c);
  insert into customers(full_name, phone) values ('Twin Two', pg_temp.tx('ph_f')) returning id into c;
  insert into fx values ('twin2', c);
end $$;
select pg_temp.as_service();
do $$ declare r jsonb; begin
  r := public.web_order_paid(pg_temp.paid(pg_temp.sess('E'), 'day2', 1, 6100, 'A Different Name', pg_temp.tx('ph_e'),
         pg_temp.sg(0, '12:00'), pg_temp.sg(0, '12:01')));
  insert into tx values ('o6e_no', r->>'invoice_no');
  r := public.web_order_paid(pg_temp.paid(pg_temp.sess('F'), 'day2', 1, 6100, 'Twin Buyer', pg_temp.tx('ph_f'),
         pg_temp.sg(0, '12:00'), pg_temp.sg(0, '12:01')));
  insert into tx values ('o6f_status', r->>'status'), ('o6f_reason', r->>'review_reason');
end $$;
select pg_temp.check((select customer_id from public.invoices where invoice_no = pg_temp.tx('o6e_no')) = pg_temp.fx('cust_e')
    and (select full_name from public.customers where id = pg_temp.fx('cust_e')) = 'Existing Person',
  'O6 one customer with the buyer''s phone is the buyer, whatever the name (and keeps their name)');
select pg_temp.check(pg_temp.tx('o6f_status') = 'needs_review' and pg_temp.tx('o6f_reason') like '2 customers share%'
    and (select candidate_customer_ids @> array[pg_temp.fx('twin1'), pg_temp.fx('twin2')] from pg_temp.order_of(pg_temp.sess('F'))),
  'O6 two customers with the phone: the order waits with both as candidates');
select pg_temp.as_user('manager');
select pg_temp.check((select jsonb_array_length(x->'candidates') = 2
                        from jsonb_array_elements(public.web_orders_list(pg_temp.fx('ev'))->'orders') x
                       where x->>'stripe_session_id' = pg_temp.sess('F')),
  'O6 the waiting order lists its candidates for the Manager');
do $$ declare r jsonb; begin
  r := public.web_order_resolve((select id from pg_temp.order_of(pg_temp.sess('F'))), pg_temp.fx('twin2'), false);
  insert into tx values ('o6r_status', r->>'status'), ('o6r_no', r->>'invoice_no');
end $$;
select pg_temp.check(pg_temp.tx('o6r_status') = 'invoiced'
    and (select (customer_id, created_by) = (pg_temp.fx('twin2'), pg_temp.fx('acting')) from public.invoices where invoice_no = pg_temp.tx('o6r_no'))
    and exists (select 1 from public.audit_logs where table_name = 'web_orders' and action = 'web_order_resolved'
                  and changed_by = pg_temp.fx('manager')),
  'O6 the Manager chooses a candidate: invoiced for them, still raised by the channel''s profile, and audited');
-- The early-bird mismatch order, for a new customer after the owner fixes nothing: still refused on total.
do $$ declare r jsonb; begin
  r := public.web_order_resolve((select id from pg_temp.order_of(pg_temp.sess('D'))), null, true);
  insert into tx values ('o6n_status', r->>'status');
end $$;
select pg_temp.check(pg_temp.tx('o6n_status') = 'needs_review', 'O6 resolving does not bypass the total check');

-- ═════ O7 Refusals ═════
select pg_temp.as_service();
do $$ declare r jsonb; begin
  r := public.web_order_paid(pg_temp.paid('cs_test_O372T' || pg_temp.tx('sfx'), 'day1', 1, 6100, 'Tester', pg_temp.phone(),
         pg_temp.sg(0, '13:00'), pg_temp.sg(0, '13:01')));
  insert into tx values ('o7_test', r->>'status'), ('o7_test_reason', r->>'review_reason');
  r := public.web_order_paid(pg_temp.paid(pg_temp.sess('G'), 'day1', 1, 6100, 'Bad', pg_temp.phone(), pg_temp.sg(0, '13:00'), pg_temp.sg(0, '13:01'))
         || jsonb_build_object('livemode', false));
  insert into tx values ('o7_flag', r->>'status');
  r := public.web_order_paid(pg_temp.paid('not-a-session', 'day1', 1, 6100, 'Bad', pg_temp.phone(), pg_temp.sg(0, '13:00'), pg_temp.sg(0, '13:01')));
  insert into tx values ('o7_bad', r->>'status');
end $$;
select pg_temp.check(pg_temp.tx('o7_test') = 'refused' and pg_temp.tx('o7_test_reason') = 'A Stripe test payment'
    and not exists (select 1 from public.invoices where notes like '%cs_test_O372T%'),
  'O7 a Stripe test payment is refused (kept as refused, never invoiced)');
select pg_temp.check(pg_temp.tx('o7_flag') = 'refused' and pg_temp.tx('o7_bad') = 'refused'
    and not exists (select 1 from public.web_orders where stripe_session_id in (pg_temp.sess('G'), 'not-a-session')),
  'O7 a mismatched live flag or a malformed checkout id is refused and not kept');
update public.web_order_channels set allow_test = true where key = pg_temp.tx('channel');
do $$ declare r jsonb; begin
  r := public.web_order_paid(pg_temp.paid('cs_test_O372U' || pg_temp.tx('sfx'), 'day1', 1, 6100, 'Tester Two', pg_temp.phone(),
         pg_temp.sg(0, '13:00'), pg_temp.sg(0, '13:01')));
  insert into tx values ('o7_allowed', r->>'status');
end $$;
select pg_temp.check(pg_temp.tx('o7_allowed') = 'invoiced', 'O7 a channel that allows test payments invoices them (for local testing)');
update public.web_order_channels set allow_test = false, mode = 'off' where key = pg_temp.tx('channel');
do $$ declare r jsonb; begin
  r := public.web_order_paid(pg_temp.paid(pg_temp.sess('H'), 'day1', 1, 6100, 'Off', pg_temp.phone(), pg_temp.sg(0, '13:00'), pg_temp.sg(0, '13:01')));
  insert into tx values ('o7_off', r->>'status'), ('o7_off_reason', r->>'review_reason');
end $$;
select pg_temp.check(pg_temp.tx('o7_off') = 'refused' and pg_temp.tx('o7_off_reason') = 'The website channel is off',
  'O7 an off channel refuses orders');
update public.web_order_channels set mode = 'live' where key = pg_temp.tx('channel');

-- ═════ O8 Names ═════
select pg_temp.as_service();
do $$ declare r jsonb; g1 uuid; begin
  select g.id into g1 from public.event_guests g join public.invoices i on i.id = g.invoice_id
   where i.invoice_no = pg_temp.tx('o2_no') and g.line_position = 1;
  insert into fx values ('o8_g1', g1);
  r := public.web_order_names(jsonb_build_object('channel', pg_temp.tx('channel'), 'stripe_session_id', pg_temp.sess('B'),
         'livemode', true, 'buyer', jsonb_build_object('first_name', 'Bee', 'last_name', 'Buyer', 'email', null, 'whatsapp', null),
         'attendees', jsonb_build_array(jsonb_build_object('name', 'Bee Buyer'), jsonb_build_object('name', 'Friend Of Bee', 'whatsapp', '+65 9123 0999'))));
  insert into tx values ('o8_status', r->>'status');
end $$;
select pg_temp.check(pg_temp.tx('o8_status') = 'invoiced'
    and (select string_agg(g.name, ' | ' order by g.line_position) from public.event_guests g
          join public.invoices i on i.id = g.invoice_id where i.invoice_no = pg_temp.tx('o2_no') and g.status = 'registered')
         = 'Bee Buyer | Friend Of Bee'
    and exists (select 1 from public.event_guests where id = pg_temp.fx('o8_g1') and name = 'Bee Buyer' and status = 'registered')
    and exists (select 1 from public.audit_logs a join public.invoices i on i.id = a.record_id
                 where i.invoice_no = pg_temp.tx('o2_no') and a.action = 'event_ticket_people_changed'),
  'O8 the buyer''s names rename the people on the invoice, keeping their guest records, and the change is audited');
select pg_temp.check((select (c.first_name, c.last_name, c.full_name) = ('Bee', 'Buyer', 'Bee Buyer')
                        from public.customers c join public.invoices i on i.customer_id = c.id where i.invoice_no = pg_temp.tx('o2_no')),
  'O8 a customer this order made takes the name parts the buyer gave');
do $$ declare r jsonb; begin
  r := public.web_order_names(jsonb_build_object('channel', pg_temp.tx('channel'), 'stripe_session_id', pg_temp.sess('B'),
         'livemode', true, 'buyer', jsonb_build_object('first_name', 'Bee'),
         'attendees', jsonb_build_array(jsonb_build_object('name', 'Only One'))));
  insert into tx values ('o8_wrong', r->>'review_reason');
end $$;
select pg_temp.check(pg_temp.tx('o8_wrong') like 'The names do not match%'
    and (select count(*) from public.event_guests g join public.invoices i on i.id = g.invoice_id
          where i.invoice_no = pg_temp.tx('o2_no') and g.status = 'registered' and g.name = 'Only One') = 0,
  'O8 names for the wrong number of people are not used');
-- Names for a recorded order (A) are used when a live channel invoices it.
do $$ declare r jsonb; begin
  r := public.web_order_names(jsonb_build_object('channel', pg_temp.tx('channel'), 'stripe_session_id', pg_temp.sess('A'),
         'livemode', true, 'buyer', jsonb_build_object('first_name', 'Ay', 'last_name', 'Buyer'),
         'attendees', jsonb_build_array(jsonb_build_object('name', 'Ay Buyer'), jsonb_build_object('name', 'Ay Friend'))));
  insert into tx values ('o8a_status', r->>'status'), ('o8a_no', r->>'invoice_no');
  r := public.web_order_names(jsonb_build_object('channel', pg_temp.tx('channel'), 'stripe_session_id', pg_temp.sess('Z'),
         'livemode', true, 'buyer', jsonb_build_object('first_name', 'Nobody'), 'attendees', jsonb_build_array(jsonb_build_object('name', 'Nobody'))));
  insert into tx values ('o8z_status', r->>'status');
end $$;
select pg_temp.check(pg_temp.tx('o8a_status') = 'invoiced'
    and (select string_agg(g.name, ' | ' order by g.line_position) from public.event_guests g
          join public.invoices i on i.id = g.invoice_id where i.invoice_no = pg_temp.tx('o8a_no') and g.status = 'registered')
         = 'Ay Buyer | Ay Friend',
  'O8 names that arrive before the invoice are used when it is made');
select pg_temp.check(pg_temp.tx('o8z_status') = 'not_found', 'O8 names for a checkout not handed in yet say so');

-- ═════ O10 What the review of 372 found ═════
-- A phone stored before the phone policy, in the local 8-digit form, is the
-- same phone as Stripe's international form.
select pg_temp.as_user('owner');
do $$ declare c uuid; begin
  insert into tx values ('ph_l', pg_temp.phone());
  alter table public.customers disable trigger zz_normalize_current_customer_phone;
  insert into customers(full_name, phone) values ('Legacy Person', substr(pg_temp.tx('ph_l'), 4)) returning id into c;
  alter table public.customers enable trigger zz_normalize_current_customer_phone;
  insert into fx values ('legacy', c);
end $$;
update public.web_order_channels set mode = 'live' where key = pg_temp.tx('channel');
select pg_temp.as_service();
do $$ declare r jsonb; begin
  r := public.web_order_paid(pg_temp.paid(pg_temp.sess('L'), 'day1', 1, 6100, 'Legacy Buyer', pg_temp.tx('ph_l'),
         pg_temp.sg(0, '14:00'), pg_temp.sg(0, '14:01')));
  insert into tx values ('o10l_no', r->>'invoice_no');
end $$;
select pg_temp.check((select customer_id from public.invoices where invoice_no = pg_temp.tx('o10l_no')) = pg_temp.fx('legacy')
    and not (select customer_created from pg_temp.order_of(pg_temp.sess('L'))),
  'O10 a customer whose phone is stored in the old local form is found, not duplicated');
-- A test payment recorded while test payments were allowed is not invoiced
-- once they are not.
update public.web_order_channels set allow_test = true, mode = 'record_only' where key = pg_temp.tx('channel');
do $$ declare r jsonb; begin
  r := public.web_order_paid(pg_temp.paid('cs_test_O372V' || pg_temp.tx('sfx'), 'day1', 1, 6100, 'Tester Three', pg_temp.phone(),
         pg_temp.sg(0, '15:00'), pg_temp.sg(0, '15:01')));
  insert into tx values ('o10t_rec', r->>'status');
end $$;
update public.web_order_channels set allow_test = false, mode = 'live' where key = pg_temp.tx('channel');
select pg_temp.as_user('manager');
do $$ declare r jsonb; begin
  r := public.web_order_resolve((select id from pg_temp.order_of('cs_test_O372V' || pg_temp.tx('sfx'))));
  insert into tx values ('o10t_res', r->>'status');
end $$;
select pg_temp.check(pg_temp.tx('o10t_rec') = 'recorded' and pg_temp.tx('o10t_res') = 'refused'
    and not exists (select 1 from public.invoices where notes like '%cs_test_O372V%'),
  'O10 a test payment recorded while allowed is refused once test payments are not');
-- Names sent again after staff corrected the customer leave the customer alone,
-- and the buyer's name parts from the first delivery stay.
select pg_temp.as_user('owner');
update public.customers set first_name = 'Corrected', last_name = 'By Staff', full_name = 'Corrected By Staff'
 where id = (select customer_id from pg_temp.order_of(pg_temp.sess('B')));
select pg_temp.as_service();
do $$ declare r jsonb; begin
  r := public.web_order_names(jsonb_build_object('channel', pg_temp.tx('channel'), 'stripe_session_id', pg_temp.sess('B'),
         'livemode', true, 'buyer', jsonb_build_object('first_name', 'Bee Changed', 'last_name', 'Again'),
         'attendees', jsonb_build_array(jsonb_build_object('name', 'Bee Buyer'), jsonb_build_object('name', 'Friend Of Bee'))));
end $$;
select pg_temp.check((select full_name from public.customers where id = (select customer_id from pg_temp.order_of(pg_temp.sess('B')))) = 'Corrected By Staff'
    and (select (buyer_first_name, buyer_last_name) = ('Bee', 'Buyer') from pg_temp.order_of(pg_temp.sess('B'))),
  'O10 names sent again do not undo a staff correction of the customer, nor change the buyer''s first name parts');
select pg_temp.check(exists (select 1 from public.audit_logs where action = 'customer_named_from_website'
                               and record_id = (select customer_id from pg_temp.order_of(pg_temp.sess('B')))),
  'O10 naming a customer from the website is audited');

-- ═════ O11 What the pre-apply review of 372 found (373) ═════
-- A customer made in advance under a guessable request id (the checkout id, or
-- the order's id, which a Manager can see while it waits) is not the order's.
update public.web_order_channels set mode = 'live' where key = pg_temp.tx('channel');
select pg_temp.as_user('staff');
do $$ declare r jsonb; begin
  insert into tx values ('ph_s1', pg_temp.phone());
  r := public.create_customer_quick('Staff Pick', null, pg_temp.phone(), null,
         p_request_id => public.web_order_uuid('web-order-customer:' || pg_temp.sess('S1')));
  insert into fx values ('pick1', (r->>'customer_id')::uuid);
end $$;
select pg_temp.as_service();
do $$ declare r jsonb; begin
  r := public.web_order_paid(pg_temp.paid(pg_temp.sess('S1'), 'day1', 1, 6100, 'Buyer Ess', pg_temp.tx('ph_s1'),
         pg_temp.sg(0, '09:00'), pg_temp.sg(0, '09:05')));
  insert into tx values ('o11s1_status', r->>'status'), ('o11s1_no', r->>'invoice_no');
end $$;
select pg_temp.check(pg_temp.tx('o11s1_status') = 'invoiced'
    and (select c.id <> pg_temp.fx('pick1') and c.phone = pg_temp.tx('ph_s1') from public.customers c
           join public.invoices i on i.customer_id = c.id where i.invoice_no = pg_temp.tx('o11s1_no'))
    and (select customer_created from pg_temp.order_of(pg_temp.sess('S1'))),
  'O11 a customer made in advance under the checkout id is not the order''s: the buyer gets their own');
update public.web_order_channels set mode = 'record_only' where key = pg_temp.tx('channel');
select pg_temp.as_service();
do $$ declare r jsonb; begin
  insert into tx values ('ph_s2', pg_temp.phone());
  r := public.web_order_paid(pg_temp.paid(pg_temp.sess('S2'), 'day1', 1, 6100, 'Buyer Tee', pg_temp.tx('ph_s2'),
         pg_temp.sg(0, '09:00'), pg_temp.sg(0, '09:05')));
end $$;
select pg_temp.as_user('manager');
do $$ declare r jsonb; begin
  r := public.create_customer_quick('Staff Pick Two', null, pg_temp.phone(), null,
         p_request_id => public.web_order_uuid('web-order-customer:' || (select id from pg_temp.order_of(pg_temp.sess('S2')))::text));
  insert into fx values ('pick2', (r->>'customer_id')::uuid);
end $$;
update public.web_order_channels set mode = 'live' where key = pg_temp.tx('channel');
do $$ declare r jsonb; begin
  r := public.web_order_resolve((select id from pg_temp.order_of(pg_temp.sess('S2'))), null, true);
  insert into tx values ('o11s2_status', r->>'status'), ('o11s2_no', r->>'invoice_no');
end $$;
select pg_temp.check(pg_temp.tx('o11s2_status') = 'invoiced'
    and (select c.id <> pg_temp.fx('pick2') and c.phone = pg_temp.tx('ph_s2') from public.customers c
           join public.invoices i on i.customer_id = c.id where i.invoice_no = pg_temp.tx('o11s2_no')),
  'O11 a customer made in advance under the order''s own id is not the order''s either');

-- Times that do not hang together wait for review.
select pg_temp.as_service();
do $$ declare r jsonb; begin
  insert into tx values ('ph_t1', pg_temp.phone()), ('ph_t2', pg_temp.phone()), ('ph_t3', pg_temp.phone()),
                        ('ph_t4', pg_temp.phone()), ('ph_t6', pg_temp.phone());
  r := public.web_order_paid(pg_temp.paid(pg_temp.sess('T1'), 'day1', 1, 6100, 'Time One', pg_temp.tx('ph_t1'),
         now() - interval '10 minutes', now() + interval '1 hour'));
  insert into tx values ('t1', r->>'status'), ('t1r', r->>'review_reason');
  r := public.web_order_paid(pg_temp.paid(pg_temp.sess('T2'), 'day1', 1, 6100, 'Time Two', pg_temp.tx('ph_t2'),
         now() - interval '5 minutes', now() - interval '30 minutes'));
  insert into tx values ('t2', r->>'status'), ('t2r', r->>'review_reason');
  -- Opened five days ago, in the early bird (S$30.50), paid four days later.
  r := public.web_order_paid(pg_temp.paid(pg_temp.sess('T3'), 'day1', 1, 3050, 'Time Three', pg_temp.tx('ph_t3'),
         now() - interval '5 days', now() - interval '1 day', true));
  insert into tx values ('t3', r->>'status'), ('t3r', r->>'review_reason');
  r := public.web_order_paid(pg_temp.paid(pg_temp.sess('T4'), 'day1', 1, 3050, 'Time Four', pg_temp.tx('ph_t4'),
         now() - interval '8 days 10 minutes', now() - interval '8 days', true));
  insert into tx values ('t4', r->>'status'), ('t4r', r->>'review_reason');
  -- A checkout that opens after the order arrived (a clock in the future).
  r := public.web_order_paid(pg_temp.paid(pg_temp.sess('T6'), 'day1', 1, 6100, 'Time Six', pg_temp.tx('ph_t6'),
         now() + interval '3 minutes', now() + interval '2 minutes'));
  insert into tx values ('t6', r->>'status'), ('t6r', r->>'review_reason');
  -- Two days late and paid in five minutes: nothing odd, so it is invoiced.
  r := public.web_order_paid(pg_temp.paid(pg_temp.sess('T5'), 'day1', 1, 3050, 'Time Five', pg_temp.phone(),
         now() - interval '2 days', now() - interval '2 days' + interval '5 minutes', true));
  insert into tx values ('t5', r->>'status'), ('t5_no', r->>'invoice_no');
end $$;
select pg_temp.check(pg_temp.tx('t1') = 'needs_review' and pg_temp.tx('t1r') like 'Stripe''s payment time is later than when the order arrived%'
    and pg_temp.tx('t2') = 'needs_review' and pg_temp.tx('t2r') like 'The checkout opened after it was paid, or after the order arrived%'
    and pg_temp.tx('t6') = 'needs_review' and pg_temp.tx('t6r') like 'The checkout opened after it was paid, or after the order arrived%'
    and pg_temp.tx('t3') = 'needs_review' and pg_temp.tx('t3r') like 'It was paid more than 2 hours after the checkout opened%'
    and pg_temp.tx('t4') = 'needs_review' and pg_temp.tx('t4r') like 'It was paid more than 7 days ago%',
  'O11 a payment in the future, before its checkout, a checkout after the order arrived, a payment more than 2 hours after its checkout, or one more than 7 days old waits for review');
select pg_temp.check(not exists (select 1 from public.invoices i
                                  where i.notes ~ (pg_temp.sess('T1') || '|' || pg_temp.sess('T2') || '|' || pg_temp.sess('T3')
                                                   || '|' || pg_temp.sess('T4') || '|' || pg_temp.sess('T6')))
    and not exists (select 1 from public.customers c
                     where c.phone in (pg_temp.tx('ph_t1'), pg_temp.tx('ph_t2'), pg_temp.tx('ph_t3'), pg_temp.tx('ph_t4'), pg_temp.tx('ph_t6'))),
  'O11 those orders leave no invoice or customer behind');
select pg_temp.check(pg_temp.tx('t5') = 'invoiced'
    and (select business_date from public.invoices where invoice_no = pg_temp.tx('t5_no'))
         = ((now() - interval '2 days') at time zone 'Asia/Singapore')::date,
  'O11 an order handed in two days late with sensible times is invoiced, dated on its checkout''s day');
select pg_temp.as_user('manager');
do $$ declare r jsonb; begin
  r := public.web_order_resolve((select id from pg_temp.order_of(pg_temp.sess('T3'))));
  insert into tx values ('t3_res', r->>'status'), ('t3_no', r->>'invoice_no');
end $$;
select pg_temp.check(pg_temp.tx('t3_res') = 'invoiced'
    and (select (business_date, total_amount) from public.invoices where invoice_no = pg_temp.tx('t3_no'))
         = (((now() - interval '5 days') at time zone 'Asia/Singapore')::date, 30.50::numeric),
  'O11 a Manager who has seen why can still create its invoice, dated on the checkout''s day');
-- Orders kept while the channel was record-only, paid ten days ago: names that
-- arrive once it is live, and a Manager's first try, show why first.
update public.web_order_channels set mode = 'record_only' where key = pg_temp.tx('channel');
select pg_temp.as_service();
do $$ declare r jsonb; begin
  r := public.web_order_paid(pg_temp.paid(pg_temp.sess('R1'), 'day1', 1, 3050, 'Old One', pg_temp.phone(),
         pg_temp.sg(0, '09:00'), pg_temp.sg(0, '09:05'), true));
  r := public.web_order_paid(pg_temp.paid(pg_temp.sess('R2'), 'day1', 1, 3050, 'Old Two', pg_temp.phone(),
         pg_temp.sg(0, '09:00'), pg_temp.sg(0, '09:05'), true));
end $$;
update public.web_orders set checkout_opened_at = now() - interval '10 days 10 minutes', paid_at = now() - interval '10 days',
                             created_at = now() - interval '10 days'
 where stripe_session_id in (pg_temp.sess('R1'), pg_temp.sess('R2'));
update public.web_order_channels set mode = 'live' where key = pg_temp.tx('channel');
do $$ declare r jsonb; begin
  r := public.web_order_names(jsonb_build_object('channel', pg_temp.tx('channel'), 'stripe_session_id', pg_temp.sess('R1'),
         'livemode', true, 'buyer', jsonb_build_object('first_name', 'Old'), 'attendees', jsonb_build_array(jsonb_build_object('name', 'Old One'))));
  insert into tx values ('r1', r->>'status'), ('r1r', r->>'review_reason');
end $$;
select pg_temp.as_user('manager');
do $$ declare r jsonb; begin
  r := public.web_order_resolve((select id from pg_temp.order_of(pg_temp.sess('R2'))));
  insert into tx values ('r2_first', r->>'status'), ('r2_reason', r->>'review_reason');
  r := public.web_order_resolve((select id from pg_temp.order_of(pg_temp.sess('R2'))));
  insert into tx values ('r2_second', r->>'status'), ('r2_no', r->>'invoice_no');
end $$;
select pg_temp.check(pg_temp.tx('r1') = 'needs_review' and pg_temp.tx('r1r') like 'It was paid more than 7 days ago%'
    and pg_temp.tx('r2_first') = 'needs_review' and pg_temp.tx('r2_reason') like 'It was paid more than 7 days ago%'
    and pg_temp.tx('r2_second') = 'invoiced'
    and (select business_date from public.invoices where invoice_no = pg_temp.tx('r2_no'))
         = ((now() - interval '10 days 10 minutes') at time zone 'Asia/Singapore')::date,
  'O11 an old recorded order is not invoiced by names, and a Manager sees why before creating its invoice');
-- The limits themselves: 5 minutes, 1 minute, 2 hours and 7 days.
select pg_temp.as_service();
do $$ declare r jsonb; begin
  r := public.web_order_paid(pg_temp.day1(pg_temp.sess('B1'), 'Edge One', pg_temp.phone(), now() - interval '10 minutes', now() + interval '4 minutes'));
  insert into tx values ('b1', r->>'status');
  r := public.web_order_paid(pg_temp.day1(pg_temp.sess('B2'), 'Edge Two', pg_temp.phone(), now() - interval '10 minutes', now() + interval '6 minutes'));
  insert into tx values ('b2', r->>'status');
  r := public.web_order_paid(pg_temp.day1(pg_temp.sess('B3'), 'Edge Three', pg_temp.phone(), now() - interval '4 minutes 30 seconds', now() - interval '5 minutes'));
  insert into tx values ('b3', r->>'status');
  r := public.web_order_paid(pg_temp.day1(pg_temp.sess('B4'), 'Edge Four', pg_temp.phone(), now() - interval '3 minutes 30 seconds', now() - interval '5 minutes'));
  insert into tx values ('b4', r->>'status');
  r := public.web_order_paid(pg_temp.day1(pg_temp.sess('B5'), 'Edge Five', pg_temp.phone(), now() - interval '1 hour 55 minutes', now() - interval '5 minutes'));
  insert into tx values ('b5', r->>'status');
  r := public.web_order_paid(pg_temp.day1(pg_temp.sess('B6'), 'Edge Six', pg_temp.phone(), now() - interval '2 hours 15 minutes', now() - interval '5 minutes'));
  insert into tx values ('b6', r->>'status');
  r := public.web_order_paid(pg_temp.day1(pg_temp.sess('B7'), 'Edge Seven', pg_temp.phone(), now() - interval '6 days 10 minutes', now() - interval '6 days'));
  insert into tx values ('b7', r->>'status');
end $$;
select pg_temp.check((pg_temp.tx('b1'), pg_temp.tx('b2'), pg_temp.tx('b3'), pg_temp.tx('b4'), pg_temp.tx('b5'), pg_temp.tx('b6'), pg_temp.tx('b7'))
                     = ('invoiced', 'needs_review', 'invoiced', 'needs_review', 'invoiced', 'needs_review', 'invoiced'),
  'O11 at the limits: paid 4 min after arrival yes, 6 no; opened 30 s after payment yes, 90 s no; paid 1h55 after the checkout yes, 2h15 no; paid 6 days ago yes');
-- Times are checked before anything else: an order with odd times while the
-- channel's profile is inactive shows the time reason, not the profile.
select pg_temp.as_user('owner');
update public.profiles set is_active = false where id = pg_temp.fx('acting');
select pg_temp.as_service();
do $$ declare r jsonb; begin
  r := public.web_order_paid(pg_temp.day1(pg_temp.sess('P1'), 'Order Pee', pg_temp.phone(), now() - interval '3 hours', now() - interval '5 minutes'));
  insert into tx values ('p1r', r->>'review_reason');
end $$;
select pg_temp.as_user('owner');
update public.profiles set is_active = true where id = pg_temp.fx('acting');
select pg_temp.check(pg_temp.tx('p1r') like 'It was paid more than 2 hours after the checkout opened%',
  'O11 the times are checked first, so odd ones are what the order shows');
-- Only a time reason lets a Manager's resolve take the times as they are: an
-- order that waited for its customer, and grew old meanwhile, shows its age first.
select pg_temp.as_service();
do $$ declare r jsonb; begin
  -- Early-bird money: by the time it is invoiced it is dated in the early bird.
  r := public.web_order_paid(pg_temp.paid(pg_temp.sess('P2'), 'day2', 1, 3050, 'Twin Again', pg_temp.tx('ph_f'),
         pg_temp.sg(0, '09:00'), pg_temp.sg(0, '09:05'), true));
  insert into tx values ('p2', r->>'review_reason');
end $$;
update public.web_orders set checkout_opened_at = now() - interval '8 days 10 minutes', paid_at = now() - interval '8 days',
                             created_at = now() - interval '8 days'
 where stripe_session_id = pg_temp.sess('P2');
select pg_temp.as_user('manager');
do $$ declare r jsonb; begin
  r := public.web_order_resolve((select id from pg_temp.order_of(pg_temp.sess('P2'))), pg_temp.fx('twin1'), false);
  insert into tx values ('p2_first', r->>'review_reason');
  r := public.web_order_resolve((select id from pg_temp.order_of(pg_temp.sess('P2'))), pg_temp.fx('twin1'), false);
  insert into tx values ('p2_second', r->>'status');
end $$;
select pg_temp.check(pg_temp.tx('p2') like '2 customers share%' and pg_temp.tx('p2_first') like 'It was paid more than 7 days ago%'
    and pg_temp.tx('p2_second') = 'invoiced',
  'O11 a Manager''s resolve skips the time checks only after a time reason was shown');
-- An invoice is never dated after today, even when a Manager accepts a
-- checkout time in the future.
select pg_temp.as_service();
do $$ declare r jsonb; begin
  r := public.web_order_paid(pg_temp.paid(pg_temp.sess('F1'), 'day1', 1, 6100, 'Future One', pg_temp.phone(),
         now() + interval '3 days', now() + interval '3 days 5 minutes'));
  insert into tx values ('f1', r->>'status');
end $$;
select pg_temp.as_user('manager');
do $$ declare r jsonb; begin
  r := public.web_order_resolve((select id from pg_temp.order_of(pg_temp.sess('F1'))));
  insert into tx values ('f1_res', r->>'status'), ('f1_no', r->>'invoice_no');
end $$;
select pg_temp.check(pg_temp.tx('f1') = 'needs_review' and pg_temp.tx('f1_res') = 'invoiced'
    and (select business_date from public.invoices where invoice_no = pg_temp.tx('f1_no')) = pg_temp.d(0),
  'O11 an invoice is never dated after today');
-- A buyer who named themselves before the invoice was made gets those name
-- parts on the new customer.
update public.web_order_channels set mode = 'record_only' where key = pg_temp.tx('channel');
select pg_temp.as_service();
do $$ declare r jsonb; begin
  r := public.web_order_paid(pg_temp.paid(pg_temp.sess('K1'), 'day1', 1, 6100, 'TAN AH KOW', pg_temp.phone(),
         pg_temp.sg(0, '09:00'), pg_temp.sg(0, '09:05')));
  r := public.web_order_names(jsonb_build_object('channel', pg_temp.tx('channel'), 'stripe_session_id', pg_temp.sess('K1'),
         'livemode', true, 'buyer', jsonb_build_object('first_name', 'Tan', 'last_name', 'Ah Kow'),
         'attendees', jsonb_build_array(jsonb_build_object('name', 'Tan Ah Kow'))));
end $$;
update public.web_order_channels set mode = 'live' where key = pg_temp.tx('channel');
select pg_temp.as_user('manager');
do $$ declare r jsonb; begin
  r := public.web_order_resolve((select id from pg_temp.order_of(pg_temp.sess('K1'))));
  insert into tx values ('k1_no', r->>'invoice_no');
end $$;
select pg_temp.check((select (c.first_name, c.last_name, c.full_name) = ('Tan', 'Ah Kow', 'Tan Ah Kow')
                        from public.customers c join public.invoices i on i.customer_id = c.id where i.invoice_no = pg_temp.tx('k1_no')),
  'O11 a buyer who named themselves before the invoice gets those name parts on the new customer');

-- New names keep what staff set on a guest: the customer they linked, and a
-- phone where the buyer gave no WhatsApp.
select pg_temp.as_service();
do $$ declare r jsonb; begin
  r := public.web_order_paid(pg_temp.paid(pg_temp.sess('N1'), 'day1', 2, 6100, 'Buyer En', pg_temp.phone(),
         pg_temp.sg(0, '09:00'), pg_temp.sg(0, '09:05')));
  insert into tx values ('n1_no', r->>'invoice_no');
end $$;
select pg_temp.as_user('owner');
do $$ declare c1 uuid; c2 uuid; begin
  insert into customers(full_name, phone) values ('Linked One', pg_temp.phone()) returning id into c1;
  insert into customers(full_name, phone) values ('Linked Two', pg_temp.phone()) returning id into c2;
  insert into fx values ('lk1', c1), ('lk2', c2);
  update public.event_guests g
     set customer_id = case g.line_position when 1 then c1 else c2 end,
         phone = case g.line_position when 1 then '+6591110001' else '+6591110002' end
    from public.invoices i where i.id = g.invoice_id and i.invoice_no = pg_temp.tx('n1_no');
end $$;
create function pg_temp.n1_people() returns text language sql as $$
  select string_agg(g.name || '/' || coalesce(g.customer_id::text, '-') || '/' || coalesce(g.phone, '-'), ' | ' order by g.line_position)
    from public.event_guests g join public.invoices i on i.id = g.invoice_id
   where i.invoice_no = pg_temp.tx('n1_no') and g.status = 'registered' $$;
create function pg_temp.n1_names(buyer_whatsapp text, friend_whatsapp text) returns jsonb language sql as $$
  select jsonb_build_object('channel', pg_temp.tx('channel'), 'stripe_session_id', pg_temp.sess('N1'), 'livemode', true,
           'buyer', jsonb_build_object('first_name', 'En', 'last_name', 'Buyer'),
           'attendees', jsonb_build_array(
             jsonb_strip_nulls(jsonb_build_object('name', 'En Buyer', 'whatsapp', buyer_whatsapp)),
             jsonb_strip_nulls(jsonb_build_object('name', 'En Friend', 'whatsapp', friend_whatsapp)))) $$;
select pg_temp.as_service();
do $$ declare r jsonb; begin
  r := public.web_order_names(pg_temp.n1_names(null, null));
  insert into tx values ('n1_status', r->>'status');
end $$;
select pg_temp.check(pg_temp.tx('n1_status') = 'invoiced'
    and pg_temp.n1_people() = 'En Buyer/' || pg_temp.fx('lk1') || '/+6591110001 | En Friend/' || pg_temp.fx('lk2') || '/+6591110002',
  'O11 new names keep the customers staff linked, and their phones where the buyer gave no WhatsApp');
-- Staff then correct a name. The same names again (the website may fill in
-- the buyer's own WhatsApp on a resend) change nothing.
select pg_temp.as_user('owner');
update public.event_guests g set name = 'En Friend Corrected', updated_by = pg_temp.fx('owner')
  from public.invoices i where i.id = g.invoice_id and i.invoice_no = pg_temp.tx('n1_no') and g.line_position = 2;
select pg_temp.as_service();
do $$ declare r jsonb; begin
  insert into tx values ('n1_audits', (select count(*) from public.audit_logs a join public.invoices i on i.id = a.record_id
                                        where i.invoice_no = pg_temp.tx('n1_no') and a.action = 'event_ticket_people_changed')::text);
  r := public.web_order_names(pg_temp.n1_names('+65 9111 0999', null));
end $$;
select pg_temp.check(pg_temp.n1_people() = 'En Buyer/' || pg_temp.fx('lk1') || '/+6591110001 | En Friend Corrected/' || pg_temp.fx('lk2') || '/+6591110002'
    and (select count(*) from public.audit_logs a join public.invoices i on i.id = a.record_id
          where i.invoice_no = pg_temp.tx('n1_no') and a.action = 'event_ticket_people_changed') = pg_temp.tx('n1_audits')::int,
  'O11 names the order already had, sent again, change nothing (a staff correction stays)');
-- A new WhatsApp for a guest is a change, and goes on (keeping the link).
do $$ declare r jsonb; begin
  r := public.web_order_names(pg_temp.n1_names(null, '+65 9111 0333'));
end $$;
select pg_temp.check(pg_temp.n1_people() = 'En Buyer/' || pg_temp.fx('lk1') || '/+6591110001 | En Friend/' || pg_temp.fx('lk2') || '/+65 9111 0333',
  'O11 a new WhatsApp for a guest goes on, keeping the customer staff linked');
-- Names that do not fit the ticket line (staff changed it) are kept, with the
-- reason the Events page shows, and go on once they fit.
select pg_temp.as_service();
do $$ declare r jsonb; begin
  r := public.web_order_paid(pg_temp.paid(pg_temp.sess('N2'), 'day1', 1, 6100, 'Buyer Nu', pg_temp.phone(),
         pg_temp.sg(0, '09:00'), pg_temp.sg(0, '09:05')));
  insert into tx values ('n2_no', r->>'invoice_no');
end $$;
update public.invoice_items ii set quantity = 2
  from public.invoices i where i.id = ii.invoice_id and i.invoice_no = pg_temp.tx('n2_no');
create function pg_temp.n2_names() returns jsonb language sql as $$
  select jsonb_build_object('channel', pg_temp.tx('channel'), 'stripe_session_id', pg_temp.sess('N2'), 'livemode', true,
           'buyer', jsonb_build_object('first_name', 'Nu'), 'attendees', jsonb_build_array(jsonb_build_object('name', 'Nu Real'))) $$;
create function pg_temp.n2_guest() returns text language sql as $$
  select string_agg(g.name, ' | ' order by g.line_position) from public.event_guests g join public.invoices i on i.id = g.invoice_id
   where i.invoice_no = pg_temp.tx('n2_no') and g.status = 'registered' $$;
do $$ declare r jsonb; begin
  r := public.web_order_names(pg_temp.n2_names());
  insert into tx values ('n2_status', r->>'status'), ('n2_reason', r->>'review_reason');
end $$;
select pg_temp.as_user('manager');
select pg_temp.check(pg_temp.tx('n2_status') = 'invoiced'
    and pg_temp.tx('n2_reason') like 'The buyer''s names are kept here but are not on the invoice: they are for 1 people and its ticket line is for 2%'
    and pg_temp.n2_guest() = 'Buyer Nu'
    and (select x->>'review_reason' from jsonb_array_elements(public.web_orders_list(pg_temp.fx('ev'))->'orders') x
          where x->>'stripe_session_id' = pg_temp.sess('N2')) = pg_temp.tx('n2_reason'),
  'O11 names that do not fit the ticket line are kept, and the Events page shows why');
update public.invoice_items ii set quantity = 1
  from public.invoices i where i.id = ii.invoice_id and i.invoice_no = pg_temp.tx('n2_no');
-- Meanwhile staff moved the invoice to another customer and unlinked the
-- buyer's guest: the buyer's line takes the invoice's customer.
update public.invoices set customer_id = pg_temp.fx('lk1') where invoice_no = pg_temp.tx('n2_no');
update public.event_guests g set customer_id = null
  from public.invoices i where i.id = g.invoice_id and i.invoice_no = pg_temp.tx('n2_no');
select pg_temp.as_service();
do $$ declare r jsonb; begin
  r := public.web_order_names(pg_temp.n2_names());
  insert into tx values ('n2_again', coalesce(r->>'review_reason', 'none'));
end $$;
select pg_temp.check(pg_temp.tx('n2_again') = 'none' and pg_temp.n2_guest() = 'Nu Real'
    and (select review_reason is null from pg_temp.order_of(pg_temp.sess('N2'))),
  'O11 once they fit, the same names sent again go on and the reason clears');
select pg_temp.check((select g.customer_id from public.event_guests g join public.invoices i on i.id = g.invoice_id
                       where i.invoice_no = pg_temp.tx('n2_no') and g.status = 'registered') = pg_temp.fx('lk1'),
  'O11 the buyer''s line takes the invoice''s customer, which staff may have changed');

-- The names go on the line the order made, not another line staff added; if
-- that line is gone and the pass has several or none, the names wait, and a
-- Manager puts them on once there is one.
select pg_temp.as_service();
do $$ declare r jsonb; begin
  r := public.web_order_paid(pg_temp.paid(pg_temp.sess('L1'), 'day1', 1, 6100, 'Buyer Ell', pg_temp.phone(),
         pg_temp.sg(0, '09:00'), pg_temp.sg(0, '09:05')));
  insert into tx values ('l1_no', r->>'invoice_no');
end $$;
do $$ declare v_copy uuid := gen_random_uuid(); begin
  insert into public.invoice_items
  select (jsonb_populate_record(null::public.invoice_items, to_jsonb(ii) || jsonb_build_object('id', v_copy))).*
    from public.invoice_items ii join public.invoices i on i.id = ii.invoice_id
   where i.invoice_no = pg_temp.tx('l1_no') and ii.line_kind = 'event_ticket';
  insert into fx values ('l1_copy', v_copy);
end $$;
create function pg_temp.l1_names(n text) returns jsonb language sql as $$
  select jsonb_build_object('channel', pg_temp.tx('channel'), 'stripe_session_id', pg_temp.sess('L1'), 'livemode', true,
           'buyer', jsonb_build_object('first_name', 'Ell'), 'attendees', jsonb_build_array(jsonb_build_object('name', n))) $$;
do $$ declare r jsonb; begin
  r := public.web_order_names(pg_temp.l1_names('Ell Real'));
end $$;
select pg_temp.check((select string_agg(g.name, ' | ') from public.event_guests g
                       where g.invoice_item_id = (select invoice_item_id from pg_temp.order_of(pg_temp.sess('L1'))) and g.status = 'registered') = 'Ell Real'
    and not exists (select 1 from public.event_guests g where g.invoice_item_id = pg_temp.fx('l1_copy')),
  'O11 the names go on the line the order made, not on another line on the invoice');
update public.web_orders set invoice_item_id = null where stripe_session_id = pg_temp.sess('L1');
do $$ declare r jsonb; begin
  r := public.web_order_names(pg_temp.l1_names('Ell Renamed'));
  insert into tx values ('l1_two', r->>'review_reason');
end $$;
delete from public.invoice_items where id = pg_temp.fx('l1_copy');
select pg_temp.as_user('manager');
do $$ declare r jsonb; begin
  r := public.web_order_apply_names((select id from pg_temp.order_of(pg_temp.sess('L1'))));
  insert into tx values ('l1_applied', coalesce(r->>'review_reason', 'none'));
end $$;
select pg_temp.check(pg_temp.tx('l1_two') like '%more than one ticket line for this pass'
    and pg_temp.tx('l1_applied') = 'none'
    and (select string_agg(g.name, ' | ') from public.event_guests g join public.invoices i on i.id = g.invoice_id
          where i.invoice_no = pg_temp.tx('l1_no') and g.status = 'registered') = 'Ell Renamed'
    and (select review_reason is null and invoice_item_id is not null from pg_temp.order_of(pg_temp.sess('L1')))
    and exists (select 1 from public.audit_logs where action = 'web_order_names_applied' and changed_by = pg_temp.fx('manager')),
  'O11 with two lines for the pass the names wait; with one again, a Manager puts them on (audited)');
select pg_temp.as_service();
do $$ declare r jsonb; begin
  r := public.web_order_paid(pg_temp.paid(pg_temp.sess('L2'), 'day1', 1, 6100, 'Buyer Elle', pg_temp.phone(),
         pg_temp.sg(0, '09:00'), pg_temp.sg(0, '09:05')));
  insert into tx values ('l2_no', r->>'invoice_no');
end $$;
delete from public.invoice_items ii using public.invoices i where i.id = ii.invoice_id and i.invoice_no = pg_temp.tx('l2_no');
do $$ declare r jsonb; begin
  r := public.web_order_names(jsonb_build_object('channel', pg_temp.tx('channel'), 'stripe_session_id', pg_temp.sess('L2'), 'livemode', true,
         'buyer', jsonb_build_object('first_name', 'Elle'), 'attendees', jsonb_build_array(jsonb_build_object('name', 'Elle Real'))));
  insert into tx values ('l2_reason', r->>'review_reason');
end $$;
select pg_temp.check(pg_temp.tx('l2_reason') like '%it has no ticket line for this pass',
  'O11 names for an invoice whose ticket line is gone are kept, with the reason');

-- ═════ O9 Who may do what ═════
select pg_temp.check(not has_function_privilege('authenticated', 'public.web_order_paid(jsonb)', 'execute')
    and not has_function_privilege('authenticated', 'public.web_order_names(jsonb)', 'execute')
    and not has_function_privilege('anon', 'public.web_orders_list(uuid)', 'execute')
    and has_function_privilege('service_role', 'public.web_order_paid(jsonb)', 'execute')
    and not has_table_privilege('authenticated', 'public.web_orders', 'select'),
  'O9 only the service role hands orders in; the tables are not reachable directly');
select pg_temp.as_user('staff');
select pg_temp.check(pg_temp.err(format('select public.web_orders_list(%L)', pg_temp.fx('ev'))) ~ 'Owner, Admin or Manager'
    and pg_temp.err(format('select public.web_order_resolve(%L)', (select id from pg_temp.order_of(pg_temp.sess('D'))))) ~ 'Owner, Admin or Manager'
    and pg_temp.err(format('select public.web_order_apply_names(%L)', (select id from pg_temp.order_of(pg_temp.sess('B'))))) ~ 'Owner, Admin or Manager',
  'O9 staff neither see nor resolve website orders, nor put names on');
select pg_temp.as_user('manager2');
select pg_temp.check(pg_temp.err(format('select public.web_orders_list(%L)', pg_temp.fx('ev'))) ~ 'access',
  'O9 a manager of another store does not see them');
select pg_temp.as_user('manager');
select pg_temp.check(pg_temp.err(format('select public.web_order_channel_set_mode(%L, ''off'')', pg_temp.tx('channel'))) ~ 'Only an Owner'
    and (public.web_orders_list(pg_temp.fx('ev'))->>'can_switch')::boolean = false,
  'O9 a manager cannot switch the channel');
select pg_temp.as_user('owner');
select public.web_order_channel_set_mode(pg_temp.tx('channel'), 'record_only');
select pg_temp.check((select mode from public.web_order_channels where key = pg_temp.tx('channel')) = 'record_only'
    and (public.web_orders_list(pg_temp.fx('ev'))->>'can_switch')::boolean,
  'O9 an owner switches the channel');

-- ═════ O12 HitPay (376) ═════
select pg_temp.as_user('owner');
update public.web_order_channels set mode = 'live', allow_test = false where key = pg_temp.tx('channel');
-- One paid HitPay order as the edge function hands it in: HitPay's payment request id where Stripe's session goes.
create function pg_temp.hitpay(req text, ticket text, qty int, unit_cents int, buyer text, phone text,
  opened timestamptz, paid timestamptz, live boolean default true, early boolean default false) returns jsonb language sql as
$$ select pg_temp.paid(req, ticket, qty, unit_cents, buyer, phone, opened, paid, early)
       || jsonb_build_object('provider', 'hitpay', 'stripe_payment_intent', md5('pay' || req)::uuid::text, 'livemode', live) $$;
select pg_temp.as_service();
do $$ declare r jsonb; begin
  insert into tx values ('hp_a', gen_random_uuid()::text), ('ph_hp', pg_temp.phone());
  r := public.web_order_paid(pg_temp.hitpay(pg_temp.tx('hp_a'), 'both', 1, 9400, 'Hit Buyer', pg_temp.tx('ph_hp'),
         pg_temp.sg(0, '11:00'), pg_temp.sg(0, '11:04')));
  insert into tx values ('hp_a_status', r->>'status'), ('hp_a_no', r->>'invoice_no');
  r := public.web_order_paid(pg_temp.hitpay(pg_temp.tx('hp_a'), 'both', 1, 9400, 'Hit Buyer', pg_temp.tx('ph_hp'),
         pg_temp.sg(0, '11:00'), pg_temp.sg(0, '11:04')));
  insert into tx values ('hp_a_again', r->>'invoice_no');
end $$;
select pg_temp.check(pg_temp.tx('hp_a_status') = 'invoiced' and pg_temp.tx('hp_a_again') = pg_temp.tx('hp_a_no')
    and (select provider from pg_temp.order_of(pg_temp.tx('hp_a'))) = 'hitpay'
    and (select count(*) from public.invoices where notes like '%' || pg_temp.tx('hp_a') || '%') = 1
    and (select count(*) from public.invoice_payments p join public.invoices i on i.id = p.invoice_id
          where i.invoice_no = pg_temp.tx('hp_a_no')) = 1,
  'O12 a HitPay order on a live channel is invoiced once, and kept as a HitPay order');
select pg_temp.check((select (p.payment_method_id, p.amount, p.payment_reference)
                            = ((select id from public.payment_methods where name = 'HitPay (online)'), 94.00::numeric,
                               md5('pay' || pg_temp.tx('hp_a'))::uuid::text)
                        from public.invoice_payments p join public.invoices i on i.id = p.invoice_id
                       where i.invoice_no = pg_temp.tx('hp_a_no'))
    and (select notes from public.invoices where invoice_no = pg_temp.tx('hp_a_no')) = 'Website order · HitPay ' || pg_temp.tx('hp_a'),
  'O12 its invoice is paid with HitPay (online), for what HitPay charged, with HitPay''s payment id as reference, and its notes name HitPay');

do $$ declare r jsonb; begin
  insert into tx values ('hp_t', gen_random_uuid()::text);
  r := public.web_order_paid(pg_temp.hitpay(pg_temp.tx('hp_t'), 'day1', 1, 6100, 'Sandbox Buyer', pg_temp.phone(),
         pg_temp.sg(0, '11:10'), pg_temp.sg(0, '11:12'), false));
  insert into tx values ('hp_t_status', r->>'status'), ('hp_t_reason', r->>'review_reason');
end $$;
select pg_temp.check(pg_temp.tx('hp_t_status') = 'refused' and pg_temp.tx('hp_t_reason') = 'A HitPay test payment'
    and (select status from pg_temp.order_of(pg_temp.tx('hp_t'))) = 'refused'
    and not exists (select 1 from public.invoices where notes like '%' || pg_temp.tx('hp_t') || '%'),
  'O12 a HitPay sandbox payment is refused while the channel does not accept test orders');

do $$ declare r jsonb; begin
  r := public.web_order_paid(pg_temp.hitpay('cs_live_O376' || pg_temp.tx('sfx') || 'X', 'day1', 1, 6100, 'Bad One',
         pg_temp.phone(), pg_temp.sg(0, '11:20'), pg_temp.sg(0, '11:21')));
  insert into tx values ('hp_bad1', r->>'review_reason');
  r := public.web_order_paid(pg_temp.hitpay(upper(gen_random_uuid()::text), 'day1', 1, 6100, 'Bad Two',
         pg_temp.phone(), pg_temp.sg(0, '11:20'), pg_temp.sg(0, '11:21')));
  insert into tx values ('hp_bad2', r->>'review_reason');
  r := public.web_order_paid(pg_temp.paid(gen_random_uuid()::text, 'day1', 1, 6100, 'Bad Three', pg_temp.phone(),
         pg_temp.sg(0, '11:20'), pg_temp.sg(0, '11:21')) || jsonb_build_object('provider', 'paypal'));
  insert into tx values ('hp_bad3', r->>'review_reason');
  r := public.web_order_paid(pg_temp.paid(gen_random_uuid()::text, 'day1', 1, 6100, 'Bad Four', pg_temp.phone(),
         pg_temp.sg(0, '11:20'), pg_temp.sg(0, '11:21')));
  insert into tx values ('hp_bad4', r->>'review_reason');
end $$;
select pg_temp.check(pg_temp.tx('hp_bad1') = 'Not a HitPay payment request id' and pg_temp.tx('hp_bad2') = 'Not a HitPay payment request id'
    and pg_temp.tx('hp_bad3') = 'Unknown payment provider' and pg_temp.tx('hp_bad4') = 'Not a Stripe checkout id'
    and not exists (select 1 from public.web_orders where stripe_session_id like 'cs_live_O376%'
                       or buyer_name in ('Bad One', 'Bad Two', 'Bad Three', 'Bad Four')),
  'O12 a malformed HitPay id, an unknown provider, or a HitPay id sent as a Stripe order is refused and not kept');

do $$ declare r jsonb; begin
  insert into tx values ('hp_late', gen_random_uuid()::text);
  -- Opened yesterday morning (still the early bird), paid three hours later.
  r := public.web_order_paid(pg_temp.hitpay(pg_temp.tx('hp_late'), 'day2', 1, 3050, 'Late Buyer', pg_temp.phone(),
         pg_temp.sg(-1, '06:00'), pg_temp.sg(-1, '09:00'), true, true));
  insert into tx values ('hp_late_status', r->>'status'), ('hp_late_reason', r->>'review_reason');
end $$;
select pg_temp.as_user('manager');
do $$ declare r jsonb; begin
  r := public.web_order_resolve((select id from pg_temp.order_of(pg_temp.tx('hp_late'))));
  insert into tx values ('hp_late_resolved', r->>'status');
end $$;
select pg_temp.check(pg_temp.tx('hp_late_status') = 'needs_review'
    and pg_temp.tx('hp_late_reason') = 'It was paid more than 2 hours after the checkout opened. Check the payment in HitPay before creating its invoice'
    and pg_temp.tx('hp_late_resolved') = 'invoiced',
  'O12 a HitPay time reason names HitPay, and a Manager who has seen it creates the invoice');

select pg_temp.as_user('owner');
do $$ declare pm uuid; begin
  insert into public.payment_methods (name, is_active) values ('O376 HitPay alt ' || pg_temp.tx('sfx'), true) returning id into pm;
  insert into fx values ('hp_alt', pm);
  update public.web_order_channels set hitpay_payment_method_id = pm where key = pg_temp.tx('channel');
end $$;
select pg_temp.as_service();
do $$ declare r jsonb; begin
  insert into tx values ('hp_b', gen_random_uuid()::text);
  r := public.web_order_paid(pg_temp.hitpay(pg_temp.tx('hp_b'), 'day1', 1, 6100, 'Alt Buyer', pg_temp.phone(),
         pg_temp.sg(0, '11:30'), pg_temp.sg(0, '11:31')));
  insert into tx values ('hp_b_no', r->>'invoice_no');
end $$;
select pg_temp.check((select p.payment_method_id from public.invoice_payments p join public.invoices i on i.id = p.invoice_id
                       where i.invoice_no = pg_temp.tx('hp_b_no')) = pg_temp.fx('hp_alt'),
  'O12 a channel''s own HitPay method is used when it names one');

do $$ declare r jsonb; begin
  r := public.web_order_names(jsonb_build_object('channel', pg_temp.tx('channel'), 'stripe_session_id', pg_temp.tx('hp_a'),
         'livemode', true, 'buyer', jsonb_build_object('first_name', 'Hit', 'last_name', 'Buyer', 'email', null, 'whatsapp', null),
         'attendees', jsonb_build_array(jsonb_build_object('name', 'Hit Attendee'))));
  insert into tx values ('hp_names', r->>'status');
end $$;
select pg_temp.check(pg_temp.tx('hp_names') = 'invoiced'
    and exists (select 1 from public.event_guests g join public.invoices i on i.id = g.invoice_id
                 where i.invoice_no = pg_temp.tx('hp_a_no') and g.name = 'Hit Attendee' and g.status = 'registered'),
  'O12 the buyer''s names go on a HitPay order''s invoice');

select pg_temp.as_user('manager');
select pg_temp.check(
    (select o->>'provider' from jsonb_array_elements(public.web_orders_list(pg_temp.fx('ev'))->'orders') o
      where o->>'stripe_session_id' = pg_temp.tx('hp_a')) = 'hitpay'
    and (select o->>'provider' from jsonb_array_elements(public.web_orders_list(pg_temp.fx('ev'))->'orders') o
      where o->>'stripe_session_id' = pg_temp.sess('B')) = 'stripe'
    and public.web_orders_list(pg_temp.fx('ev'))->'channel'->>'hitpay_payment_method_name' = 'O376 HitPay alt ' || pg_temp.tx('sfx'),
  'O12 the list says each order''s provider and the channel''s HitPay method');

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All website order checks passed.';
end $$;
rollback;
