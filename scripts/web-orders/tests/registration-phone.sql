-- Website orders take the buyer's WhatsApp from the registration (403, on
-- 372, 373, 376, 380 and 382).
--
--   R0  Before 403: the functions it patches and relies on are production's
--       (md5 of pg_get_functiondef, read 8 Oct 2026), so it is tested against
--       production's bodies. It refuses, changing nothing, when one it
--       patches or relies on is not, or when another overload of a patched
--       one exists.
--   R1  403 installs the md5s its header records and leaves the grants of
--       every function it patches or relies on as they were; run again, it
--       changes nothing.
--   R2  A HitPay order with no buyer phone on a live channel waits: needs
--       review, the phone reason, no candidates, no invoice.
--   R3  Its registration's WhatsApp matches exactly one customer (stored in
--       the local form): the phone is saved and audited, and the order is
--       invoiced for that customer with the registered names on its ticket;
--       no customer is made.
--   R4  It matches none: a new customer with that phone, the registered name
--       parts and the channel's source and details; the invoice is theirs.
--   R5  It matches two: the order waits with both as its candidates; a
--       Manager then chooses one and it is invoiced for them.
--   R6  A phone the payment gave is never replaced, whatever the
--       registration says, and the order is not matched again: not even one
--       the phone policy cannot read, whose order waits for staff to find
--       the customer.
--   R7  A record-only or off channel keeps the phone and makes no invoice; a
--       Manager's Match automatically then uses it.
--   R8  An order waiting for another reason (a time rule; a pass not linked
--       to a ticket, even once it is) takes the phone but is not matched
--       again; nor is a test payment the channel no longer accepts (and the
--       names do not refuse it). One registered more than 7 days after its
--       payment is held by 373's rule, judged now, until a Manager has seen
--       it; their Match automatically then uses the WhatsApp.
--   R9  Refused and invoiced orders are unchanged: no phone, no audit row, no
--       new invoice; an invoiced order's names still go on its ticket.
--   R10 The same names message twice creates nothing twice (invoices,
--       payments, customers, guests, audit rows) and answers the same; a later
--       one with another WhatsApp changes no saved phone.
--   R11 Names before the payment change nothing; sent again after it, they
--       match.
--   R12 A passing fault while matching again keeps the names and the phone,
--       and the order waits for staff with a reason that says the invoice
--       must be created (the website does not send the names again); a
--       Manager's Match automatically then makes it.
--   R13 Staff-link orders are not reached ('names' does not find them).
--   R14 web_order_resolve takes any customer staff find, a candidate or not,
--       and invoices a no-phone order that way; a new customer, or Match
--       automatically, still needs a phone.
--   R15 web_orders_list carries the registered name parts, whether the phone
--       can be read and whether it came from the registration.
--   R16 "Hold back and wait": an order waiting for its phone whose
--       registration's WhatsApp is the phone of the customer of a ticket
--       invoice made by hand for the event, which no website order has, is
--       not invoiced. It waits with a reason that says so and the customers
--       with the phone as candidates; the names, the phone and its audit row
--       are kept; nothing is made. The same names again, the payment
--       delivered again, or a later registration with another WhatsApp
--       change nothing.
--   R17 The same when the WhatsApp is a guest's on that invoice, not its
--       customer's.
--   R18 No hold for an invoice made by hand that is cancelled, refunded,
--       linked to another website order, or for another event: the order is
--       invoiced as before.
--   R19 After a hold the list shows its hint (the invoice made by hand, by
--       number, to the Manager), and a Manager links the order to that
--       invoice (Link invoice) or creates its invoice (Match automatically,
--       by the WhatsApp).
--   R20 The hold is for matching again alone: a recorded order on a live
--       channel (recorded while the channel only recorded) is matched when
--       its names come, by the WhatsApp, as at payment, with or without an
--       invoice made by hand with that phone.
--
-- Run from the repository's root (it reads 403 to apply it as one unit, as
-- the migration tool does), after 373, 376, 380 and 382: begin; 373, 376,
-- 380, 382, then this, all rolled back (the other web order suites run the
-- same way).
--
-- Every check runs, then the file fails if any did. Disposable database only;
-- everything is rolled back. Fixtures carry a random suffix; phones are made
-- up (+65 9140 ....), names and emails are fixtures.
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
-- The edge function calls as the service role: no user at all.
create function pg_temp.as_service() returns void language sql as
$$ select set_config('request.jwt.claim.sub', '', true) $$;
-- The error a statement (or a whole file) raises, or null when it succeeds.
-- Inside the exception block a failure leaves nothing behind, as a migration
-- applied in one transaction.
create function pg_temp.err(q text) returns text language plpgsql as
$$begin execute q; return null; exception when others then return sqlerrm; end$$;
create function pg_temp.d(n int) returns date language sql as $$ select public.sg_today() + n $$;
-- A made-up phone no customer, order or earlier pick has.
create function pg_temp.phone() returns text language sql volatile as $$
  select '+659140' || lpad(n::text, 4, '0') from generate_series(0, 9999) n
   where not exists (select 1 from public.customers c
                      where regexp_replace(coalesce(c.phone, ''), '\D', '', 'g') in ('659140' || lpad(n::text, 4, '0'), '9140' || lpad(n::text, 4, '0')))
     and not exists (select 1 from public.web_orders w
                      where regexp_replace(coalesce(w.buyer_phone, ''), '\D', '', 'g') = '659140' || lpad(n::text, 4, '0'))
     and not exists (select 1 from tx where regexp_replace(tx.v, '\D', '', 'g') = '659140' || lpad(n::text, 4, '0'))
   order by random() limit 1
$$;
create function pg_temp.new_phone(key text) returns text language sql as
$$ insert into tx values ('ph_' || key, pg_temp.phone()) returning v $$;
create function pg_temp.ph(key text) returns text language sql as $$ select pg_temp.tx('ph_' || key) $$;
create function pg_temp.customer(key text, gname text, phone text) returns uuid language sql as
$$ with c as (insert into public.customers(full_name, phone) values (gname || ' ' || pg_temp.tx('sfx'), phone) returning id)
   insert into fx select key, id from c returning v $$;
-- A HitPay payment request id (a lower-case uuid) for a tag.
create function pg_temp.hp(tag text) returns text language sql as
$$ select md5('r403-hitpay:' || pg_temp.tx('sfx') || ':' || tag)::uuid::text $$;
-- One HitPay order as the edge function hands it in. HitPay gave no name, so
-- the website sends "Website buyer"; the phone is what HitPay gave (none, as
-- a rule). Checkout opened 3 minutes and paid 2 minutes before it arrives.
create function pg_temp.paid(tag text, phone text, qty int default 1, live boolean default true,
  opened timestamptz default null) returns jsonb language sql as
$$ select jsonb_build_object('channel', pg_temp.tx('channel'), 'provider', 'hitpay', 'stripe_session_id', pg_temp.hp(tag),
     'stripe_payment_intent', pg_temp.hp('pay-' || tag), 'livemode', live, 'ticket', 'day1', 'quantity', qty,
     'unit_amount_cents', 6100, 'amount_total_cents', 6100 * qty, 'early_bird', false,
     'buyer', jsonb_build_object('name', 'Website buyer', 'email', 'r403-' || lower(tag) || '@sig.invalid', 'phone', phone),
     'checkout_opened_at', coalesce(opened, now() - interval '3 minutes'), 'paid_at', now() - interval '2 minutes') $$;
-- The registration, as the website sends it: the buyer's name parts, email and
-- WhatsApp, and one name per person (the buyer first, with no WhatsApp of
-- their own, as the website's form leaves it).
create function pg_temp.names(tag text, whatsapp text, qty int default 1, live boolean default true,
  session text default null) returns jsonb language sql as
$$ select jsonb_build_object('channel', pg_temp.tx('channel'), 'provider', 'hitpay',
     'stripe_session_id', coalesce(session, pg_temp.hp(tag)), 'livemode', live,
     'buyer', jsonb_build_object('first_name', 'Fixture', 'last_name', 'Buyer ' || tag,
                                 'email', 'r403-' || lower(tag) || '@sig.invalid', 'whatsapp', whatsapp),
     'attendees', (select jsonb_agg(jsonb_build_object('name', case when k = 1 then 'Fixture Buyer ' || tag else 'Fixture Guest ' || tag || '-' || k end,
                                                      'email', null, 'whatsapp', null) order by k)
                     from generate_series(1, qty) k)) $$;
create function pg_temp.ord(tag text) returns public.web_orders language sql as
$$ select * from public.web_orders where stripe_session_id = pg_temp.hp(tag) $$;
create function pg_temp.inv(tag text) returns public.invoices language sql as
$$ select i.* from public.invoices i join public.web_orders w on w.invoice_id = i.id where w.stripe_session_id = pg_temp.hp(tag) $$;
-- The people on an order's invoice: name / phone / whose customer.
create function pg_temp.guests(tag text) returns text language sql as
$$ select string_agg(g.name || ' / ' || coalesce(g.phone, '-') || ' / '
                     || case when g.customer_id is null then '-' when g.customer_id = i.customer_id then 'the buyer' else 'another' end,
                     ' | ' order by g.line_position)
     from public.event_guests g join public.invoices i on i.id = g.invoice_id
    where i.id = (pg_temp.inv(tag)).id and g.status = 'registered' $$;
create function pg_temp.audits(tag text) returns bigint language sql as
$$ select count(*) from public.audit_logs a
    where a.record_id = (pg_temp.ord(tag)).id and a.table_name = 'web_orders' and a.action = 'web_order_phone_from_registration' $$;
-- What the fixtures' store and event hold, to show nothing was made twice.
create function pg_temp.snap() returns jsonb language sql as
$$ select jsonb_build_object(
     'invoices', (select count(*) from public.invoices where store_id = pg_temp.fx('van')),
     'payments', (select count(*) from public.invoice_payments p join public.invoices i on i.id = p.invoice_id
                   where i.store_id = pg_temp.fx('van')),
     'customers', (select count(*) from public.customers),
     'guests', (select count(*) from public.event_guests where event_id = pg_temp.fx('ev')),
     'audits', (select count(*) from public.audit_logs where action = 'web_order_phone_from_registration'),
     'orders', (select jsonb_agg(jsonb_build_array(w.status, w.buyer_phone, w.invoice_id, w.customer_id, w.review_reason,
                                                   w.candidate_customer_ids) order by w.stripe_session_id)
                  from public.web_orders w where w.channel = pg_temp.tx('channel'))) $$;
create function pg_temp.touch(fn regprocedure) returns void language plpgsql as
$$begin execute regexp_replace(pg_get_functiondef(fn), '\$function\$\s*$', E'-- changed\n$function$'); end$$;
-- The phone reason (web_order_customer).
insert into tx values ('no_phone', 'The buyer''s phone number could not be read, so the customer must be chosen');

-- 403 as the migration tool applies it, and the md5s its header records.
\set m403 `cat supabase/403_website_order_phone_from_registration.sql`
insert into tx values ('m403', :'m403');
create function pg_temp.m403() returns text language sql as $$ select pg_temp.tx('m403') $$;
create function pg_temp.recorded_md5(fn text) returns text language sql as
$$ select (regexp_match(pg_temp.m403(), 'AFTER \(for later guards\):.*?--   ' || replace(replace(fn, '(', '\('), ')', '\)') || '\s+([0-9a-f]{32})'))[1] $$;
-- What 403 patches and relies on, with production's md5s (8 Oct 2026).
create temp table prod(fn text primary key, md5 text, patched boolean);
insert into prod values
  ('public.web_order_names(jsonb)', 'aa7926944b7cfb4a5d549c62c298cdb3', true),
  ('public.web_orders_list(uuid)', 'fa7b5e6baaac862b3435779d59bfa6b1', true),
  ('public.web_order_paid(jsonb)', '2b9aa2607e6ce7918216cf064d969f4a', false),
  ('public.web_order_make_invoice(uuid,uuid,boolean,boolean)', 'a89168963591c78841c5dc37c12162b8', false),
  ('public.web_order_customer(public.web_orders,public.web_order_channels,uuid,boolean)', '0b362a76ac3b0f161abc9bfd1a001b20', false),
  ('public.web_order_resolve(uuid,uuid,boolean)', '19736dc2ca96cf2b01a6a5bbfc9c9b49', false),
  ('public.web_order_phone_customers(text)', '7a42cbcbbfadd5b91e7aa3a41b68c7e8', false),
  ('public.web_order_hand_invoices(public.web_orders,public.web_order_channels)', '11622af802bf89cd0fec4fb02d1970b9', false),
  ('public.normalize_customer_phone(text)', 'b2bfac910e0c9eff402ba44e19750bee', false),
  ('public.web_order_people(public.web_orders,uuid)', '3ae3ffcdbac166868e3e06ec45485b37', false),
  ('public.web_order_apply_names(uuid)', '863426cdc5cd8d07acc2a12893e18210', false),
  ('public.web_order_rename_people(uuid)', '6cee4a256e7ce27d40f6889ba044da58', false),
  ('public.web_order_door(jsonb)', '72401d643162c7082f7d15f39ab88de0', false),
  ('public.web_order_sync(text)', '69dcb1b15f20f7343c1976efa8318b44', false),
  ('public.event_guest_list(uuid)', 'cbe2f3ef06fe97e59fc2e3b19fd35cac', false),
  ('public.write_audit_ex(text,uuid,text,jsonb,jsonb,text,text,uuid,text,text)', 'c705c733e213a27f0dc32d54322cc855', false);
create function pg_temp.md5_of(fn text) returns text language sql as
$$ select md5(pg_get_functiondef(to_regprocedure(fn))) $$;
create function pg_temp.acls() returns text language sql as
$$ select string_agg(p.fn || '=' || coalesce((select proacl::text from pg_proc where oid = to_regprocedure(p.fn)), '-'), ';' order by p.fn) from prod p $$;

-- ═════ Fixtures ═════
do $$
declare sfx text := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  u uuid; k text; st uuid; ev uuid; o1 uuid; src uuid;
begin
  insert into tx values ('sfx', sfx), ('channel', 'r403-' || lower(sfx));
  foreach k in array array['owner','acting','manager','staff'] loop
    u := gen_random_uuid();
    insert into auth.users(id, email) values (u, 'r403-' || k || '-' || lower(sfx) || '@sig.invalid');
    insert into profiles(id, full_name, email, role)
    values (u, 'R403 ' || initcap(k) || ' ' || sfx, 'r403-' || k || '-' || lower(sfx) || '@sig.invalid',
            case k when 'staff' then 'staff' when 'manager' then 'manager' else 'owner' end::user_role);
    insert into fx values (k, u);
  end loop;
  perform set_config('request.jwt.claim.sub', pg_temp.fx('owner')::text, true);
  insert into stores(name, code, country_code) values ('R403 Van ' || sfx, 'R403V' || sfx, 'SG') returning id into st;
  insert into fx values ('van', st);
  insert into user_store_assignments(user_id, store_id) values (pg_temp.fx('manager'), st), (pg_temp.fx('staff'), st);
  -- No early bird; the seminar is in a week.
  ev := public.event_save(jsonb_build_object('name', 'R403 Seminar ' || sfx,
    'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(7))), 'store_ids', jsonb_build_array(st),
    'options', jsonb_build_array(jsonb_build_object('name', '1 Day', 'days_count', 1, 'price', 61))));
  select id into o1 from public.event_ticket_options where event_id = ev and name = '1 Day';
  insert into fx values ('ev', ev), ('day1', o1);
  insert into customer_source_options(label, is_active, requires_details, sort_order)
  values ('R403 Event ' || sfx, true, true, 9999) returning id into src;
  insert into fx values ('src', src), ('stripe', (select id from public.payment_methods where name = 'Stripe (online)')),
                        ('hitpay', (select id from public.payment_methods where name = 'HitPay (online)'));
  insert into public.web_order_channels (key, event_id, ticket_map, store_id, acting_profile_id, payment_method_id,
                                         source_option_id, source_details, mode)
  values (pg_temp.tx('channel'), ev,
          jsonb_build_object('day1', jsonb_build_object('option_id', o1, 'days', jsonb_build_array(pg_temp.d(7)))),
          st, pg_temp.fx('acting'), pg_temp.fx('stripe'), src, 'R403 Seminar (website)', 'live');
end $$;

-- ═════ R0 Production's functions, and 403's refusals ═════
select pg_temp.check((select bool_and(pg_temp.md5_of(fn) = md5) from prod),
  'R0 the functions 403 patches and relies on are production''s (md5 of pg_get_functiondef, 8 Oct 2026): '
  || coalesce((select string_agg(fn, ', ') from prod where pg_temp.md5_of(fn) is distinct from md5), 'all match'));
insert into tx values ('acl_before', pg_temp.acls());
-- Each refusal is tried on a changed copy and undone; what it left is read
-- before the undo.
savepoint r0;
select pg_temp.touch('public.web_order_names(jsonb)');
select coalesce(pg_temp.err(pg_temp.m403()), 'applied') as r0_patched,
       pg_temp.md5_of('public.web_orders_list(uuid)') = 'fa7b5e6baaac862b3435779d59bfa6b1'
       and (select prosrc ~ '-- changed' from pg_proc where oid = 'public.web_order_names(jsonb)'::regprocedure) as r0_patched_kept \gset
rollback to savepoint r0;
select pg_temp.touch('public.web_order_customer(public.web_orders,public.web_order_channels,uuid,boolean)');
select coalesce(pg_temp.err(pg_temp.m403()), 'applied') as r0_relied,
       pg_temp.md5_of('public.web_order_names(jsonb)') = 'aa7926944b7cfb4a5d549c62c298cdb3'
       and pg_temp.md5_of('public.web_orders_list(uuid)') = 'fa7b5e6baaac862b3435779d59bfa6b1' as r0_relied_kept \gset
rollback to savepoint r0;
select pg_temp.touch('public.web_order_hand_invoices(public.web_orders,public.web_order_channels)');
select coalesce(pg_temp.err(pg_temp.m403()), 'applied') as r0_hand,
       pg_temp.md5_of('public.web_order_names(jsonb)') = 'aa7926944b7cfb4a5d549c62c298cdb3' as r0_hand_kept \gset
rollback to savepoint r0;
create function public.web_orders_list(p_event_key text) returns jsonb language sql as $f$ select null::jsonb $f$;
select coalesce(pg_temp.err(pg_temp.m403()), 'applied') as r0_overload,
       pg_temp.md5_of('public.web_order_names(jsonb)') = 'aa7926944b7cfb4a5d549c62c298cdb3' as r0_overload_kept \gset
rollback to savepoint r0;
release savepoint r0;
select pg_temp.check(:'r0_patched' like '403: public.web_order_names(jsonb) is not the version this was tested against (md5 %'
    and :'r0_patched_kept'::boolean,
  'R0 403 refuses a web_order_names that is not production''s, and changes nothing: ' || :'r0_patched');
select pg_temp.check(:'r0_relied' = '403: public.web_order_customer(public.web_orders,public.web_order_channels,uuid,boolean) '
    || 'is missing or not the version read on 8 Oct 2026. Re-read it from production and re-test before applying.'
    and :'r0_relied_kept'::boolean,
  'R0 403 refuses a function it relies on (web_order_customer) that is not production''s, and changes nothing: ' || :'r0_relied');
select pg_temp.check(:'r0_hand' = '403: public.web_order_hand_invoices(public.web_orders,public.web_order_channels) '
    || 'is missing or not the version read on 8 Oct 2026. Re-read it from production and re-test before applying.'
    and :'r0_hand_kept'::boolean,
  'R0 nor one the hold relies on (web_order_hand_invoices) that is not production''s, and changes nothing: ' || :'r0_hand');
select pg_temp.check(:'r0_overload' = '403: another overload of web_order_names or web_orders_list exists'
    and :'r0_overload_kept'::boolean,
  'R0 403 refuses when another overload of a function it patches exists, and changes nothing');
select pg_temp.check((select bool_and(pg_temp.md5_of(fn) = md5) from prod) and pg_temp.acls() = pg_temp.tx('acl_before'),
  'R0 a refusal leaves every function and grant as it was');

-- ═════ R1 Installed ═════
insert into tx values ('r1', coalesce(pg_temp.err(pg_temp.m403()), 'applied'));
select pg_temp.check(pg_temp.tx('r1') = 'applied', 'R1 403 applies: ' || pg_temp.tx('r1'));
select pg_temp.check(pg_temp.recorded_md5('web_order_names(jsonb)') is not null
    and pg_temp.md5_of('public.web_order_names(jsonb)') = pg_temp.recorded_md5('web_order_names(jsonb)')
    and pg_temp.md5_of('public.web_orders_list(uuid)') = pg_temp.recorded_md5('web_orders_list(uuid)'),
  'R1 web_order_names and web_orders_list have the AFTER md5s 403''s header records');
select pg_temp.check((select bool_and(pg_temp.md5_of(fn) = md5) from prod where not patched),
  'R1 the functions 403 relies on are unchanged');
select pg_temp.check(pg_temp.acls() = pg_temp.tx('acl_before')
    and has_function_privilege('service_role', 'public.web_order_names(jsonb)', 'execute')
    and not has_function_privilege('authenticated', 'public.web_order_names(jsonb)', 'execute')
    and not has_function_privilege('anon', 'public.web_order_names(jsonb)', 'execute')
    and has_function_privilege('authenticated', 'public.web_orders_list(uuid)', 'execute')
    and not has_function_privilege('anon', 'public.web_orders_list(uuid)', 'execute'),
  'R1 every grant is as it was: the names are the service role''s alone, the list staff''s, neither signed out');
insert into tx values ('r1_again', coalesce(pg_temp.err(pg_temp.m403()), 'applied'));
select pg_temp.check(pg_temp.tx('r1_again') = 'applied'
    and pg_temp.md5_of('public.web_order_names(jsonb)') = pg_temp.recorded_md5('web_order_names(jsonb)')
    and pg_temp.md5_of('public.web_orders_list(uuid)') = pg_temp.recorded_md5('web_orders_list(uuid)')
    and pg_temp.acls() = pg_temp.tx('acl_before'),
  'R1 run again, 403 changes nothing (the same md5s and grants)');
select pg_temp.check(not exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
                                   and p.proname in ('web_order_names', 'web_orders_list')
                                   and p.oid::regprocedure::text not in ('web_order_names(jsonb)', 'web_orders_list(uuid)')),
  'R1 no overload is added');

-- ═════ R2 No phone: the order waits ═════
select pg_temp.as_service();
do $$ declare r jsonb; begin
  r := public.web_order_paid(pg_temp.paid('A', null, 2));
  insert into tx values ('r2', r::text);
end $$;
select pg_temp.check((pg_temp.tx('r2')::jsonb ->> 'status') = 'needs_review'
    and (pg_temp.tx('r2')::jsonb ->> 'review_reason') = pg_temp.tx('no_phone')
    and (select (status, review_reason, candidate_customer_ids, invoice_id, buyer_phone, buyer_name)
                is not distinct from ('needs_review', pg_temp.tx('no_phone'), '{}'::uuid[], null::uuid, null::text, 'Website buyer')
           from pg_temp.ord('A')),
  'R2 a HitPay order with no phone waits in Needs review with the phone reason, no candidates and no invoice');

-- ═════ R3 One customer has the WhatsApp ═════
do $$ declare r jsonb; begin
  perform pg_temp.new_phone('one');
  -- Stored in the local 8-digit form: the phone policy reads it as the same phone.
  perform pg_temp.customer('one', 'R403 Existing', substr(pg_temp.ph('one'), 4));
  insert into tx values ('r3_before', pg_temp.snap()::text);
  r := public.web_order_names(pg_temp.names('A', pg_temp.ph('one'), 2));
  insert into tx values ('r3', r::text);
end $$;
select pg_temp.check((pg_temp.tx('r3')::jsonb ->> 'status') = 'invoiced'
    and (pg_temp.tx('r3')::jsonb ->> 'invoice_no') = (pg_temp.inv('A')).invoice_no
    and (pg_temp.tx('r3')::jsonb ->> 'review_reason') is null,
  'R3 the registration''s answer is the invoice made: ' || pg_temp.tx('r3'));
select pg_temp.check((select (status, buyer_phone, customer_id, customer_created, review_reason, candidate_customer_ids)
                             is not distinct from ('invoiced', pg_temp.ph('one'), pg_temp.fx('one'), false, null::text, '{}'::uuid[])
                        from pg_temp.ord('A'))
    and (pg_temp.inv('A')).customer_id = pg_temp.fx('one') and (pg_temp.inv('A')).status = 'paid'
    and (pg_temp.inv('A')).total_amount = 122.00 and (pg_temp.inv('A')).created_by = pg_temp.fx('acting'),
  'R3 the WhatsApp is the buyer phone and the order is invoiced (paid, S$122.00, by the channel''s profile) for the one customer with it');
select pg_temp.check(pg_temp.guests('A') = 'Fixture Buyer A / ' || pg_temp.ph('one') || ' / the buyer | Fixture Guest A-2 / - / -',
  'R3 the names the buyer registered are on the ticket in the same call, the buyer''s line the customer''s: ' || coalesce(pg_temp.guests('A'), '-'));
select pg_temp.check((pg_temp.snap() -> 'customers') = (pg_temp.tx('r3_before')::jsonb -> 'customers')
    and (pg_temp.snap() ->> 'invoices')::int = (pg_temp.tx('r3_before')::jsonb ->> 'invoices')::int + 1,
  'R3 one invoice, and no customer made');
select pg_temp.check(pg_temp.audits('A') = 1
    and (select (a.old_data, a.new_data, a.module, a.store_id, a.changed_by)
                is not distinct from (jsonb_build_object('buyer_phone', null), jsonb_build_object('buyer_phone', pg_temp.ph('one'), 'order_id', pg_temp.hp('A')),
                   'events'::text, pg_temp.fx('van'), null::uuid)
           from public.audit_logs a where a.record_id = (pg_temp.ord('A')).id and a.action = 'web_order_phone_from_registration'),
  'R3 an audit row says the phone came from the registration (none before), from the website (no person)');

-- ═════ R4 No customer has the WhatsApp ═════
do $$ declare r jsonb; begin
  perform public.web_order_paid(pg_temp.paid('B', null));
  perform pg_temp.new_phone('b');
  insert into tx values ('r4_before', pg_temp.snap()::text);
  r := public.web_order_names(pg_temp.names('B', pg_temp.ph('b')));
  insert into tx values ('r4', r::text);
end $$;
select pg_temp.check((pg_temp.tx('r4')::jsonb ->> 'status') = 'invoiced'
    and (select (c.phone, c.first_name, c.last_name, c.full_name, c.email, c.source_option_id, c.source_details)
                = (public.normalize_customer_phone(pg_temp.ph('b')), 'Fixture', 'Buyer B', 'Fixture Buyer B', 'r403-b@sig.invalid',
                   pg_temp.fx('src'), 'R403 Seminar (website)')
           from public.customers c where c.id = (pg_temp.inv('B')).customer_id)
    and (select customer_created and customer_id = (pg_temp.inv('B')).customer_id from pg_temp.ord('B'))
    and (pg_temp.snap() ->> 'customers')::int = (pg_temp.tx('r4_before')::jsonb ->> 'customers')::int + 1,
  'R4 none has it: one new customer with that phone, the registered name parts, the email and the channel''s source and details; the invoice is theirs');

-- ═════ R5 Two customers share the WhatsApp ═════
do $$ declare r jsonb; begin
  perform public.web_order_paid(pg_temp.paid('C', null));
  perform pg_temp.new_phone('twin');
  perform pg_temp.customer('twin1', 'R403 Twin One', pg_temp.ph('twin'));
  perform pg_temp.customer('twin2', 'R403 Twin Two', pg_temp.ph('twin'));
  insert into tx values ('r5_before', pg_temp.snap()::text);
  r := public.web_order_names(pg_temp.names('C', pg_temp.ph('twin')));
  insert into tx values ('r5', r::text);
end $$;
select pg_temp.check((pg_temp.tx('r5')::jsonb ->> 'status') = 'needs_review'
    and (select (status, buyer_phone, invoice_id, review_reason)
                is not distinct from ('needs_review', pg_temp.ph('twin'), null::uuid, '2 customers share the buyer''s phone, so the customer must be chosen')
           from pg_temp.ord('C'))
    and (select candidate_customer_ids @> array[pg_temp.fx('twin1'), pg_temp.fx('twin2')] and cardinality(candidate_customer_ids) = 2
           from pg_temp.ord('C'))
    and (pg_temp.snap() ->> 'invoices') = (pg_temp.tx('r5_before')::jsonb ->> 'invoices')
    and (pg_temp.snap() ->> 'customers') = (pg_temp.tx('r5_before')::jsonb ->> 'customers'),
  'R5 two have it: the order waits with both as candidates; nothing is invoiced and no customer made');

-- ═════ R10 The same names again ═════
do $$ declare r jsonb; begin
  insert into tx values ('r10_before', pg_temp.snap()::text);
  r := public.web_order_names(pg_temp.names('A', pg_temp.ph('one'), 2));
  insert into tx values ('r10_a', r::text);
  r := public.web_order_names(pg_temp.names('B', pg_temp.ph('b')));
  insert into tx values ('r10_b', r::text);
  r := public.web_order_names(pg_temp.names('C', pg_temp.ph('twin')));
  insert into tx values ('r10_c', r::text);
  -- A later registration with another WhatsApp (one customer has it).
  r := public.web_order_names(pg_temp.names('C', pg_temp.ph('one')));
  insert into tx values ('r10_c2', r::text);
end $$;
select pg_temp.check(pg_temp.tx('r10_a')::jsonb = pg_temp.tx('r3')::jsonb and pg_temp.tx('r10_b')::jsonb = pg_temp.tx('r4')::jsonb
    and (pg_temp.tx('r10_c')::jsonb ->> 'status') = 'needs_review',
  'R10 the same names again answer as the first time');
select pg_temp.check(pg_temp.snap() = pg_temp.tx('r10_before')::jsonb
    and pg_temp.guests('A') = 'Fixture Buyer A / ' || pg_temp.ph('one') || ' / the buyer | Fixture Guest A-2 / - / -'
    and pg_temp.audits('A') = 1 and pg_temp.audits('C') = 1,
  'R10 and make nothing twice: the same invoices, payments, customers, guests, audit rows and orders');
select pg_temp.check((select (buyer_phone, status, review_reason) = (pg_temp.ph('twin'), 'needs_review',
                                '2 customers share the buyer''s phone, so the customer must be chosen') from pg_temp.ord('C'))
    and (pg_temp.tx('r10_c2')::jsonb ->> 'status') = 'needs_review',
  'R10 a later registration with another WhatsApp changes no saved phone, and the order is not matched again');

-- R5, then: a Manager chooses one of the two.
select pg_temp.as_user('manager');
do $$ declare r jsonb; begin
  r := public.web_order_resolve((pg_temp.ord('C')).id, pg_temp.fx('twin2'), false);
  insert into tx values ('r5_resolved', r::text);
end $$;
select pg_temp.check((pg_temp.tx('r5_resolved')::jsonb ->> 'status') = 'invoiced'
    and (pg_temp.inv('C')).customer_id = pg_temp.fx('twin2') and (pg_temp.ord('C')).customer_id = pg_temp.fx('twin2'),
  'R5 a Manager chooses one of the candidates and the order is invoiced for them');

-- ═════ R6 A phone the payment gave ═════
select pg_temp.as_service();
do $$ declare r jsonb; begin
  -- Two customers have the payment's phone, so it waits; the registration
  -- names one customer's phone.
  r := public.web_order_paid(pg_temp.paid('D', pg_temp.ph('twin')));
  insert into tx values ('r6_paid', r::text);
  insert into tx values ('r6_before', pg_temp.snap()::text);
  r := public.web_order_names(pg_temp.names('D', pg_temp.ph('one')));
  insert into tx values ('r6', r::text), ('r6_after', pg_temp.snap()::text);
  -- Invoiced at payment for the one customer with its phone.
  perform pg_temp.new_phone('e');
  perform pg_temp.customer('e', 'R403 Paid Phone', pg_temp.ph('e'));
  r := public.web_order_paid(pg_temp.paid('E', pg_temp.ph('e')));
  insert into tx values ('r6_e_paid', r::text);
  r := public.web_order_names(pg_temp.names('E', pg_temp.ph('one')));
  insert into tx values ('r6_e', r::text);
end $$;
select pg_temp.check((pg_temp.tx('r6_paid')::jsonb ->> 'review_reason') = '2 customers share the buyer''s phone, so the customer must be chosen'
    and (select (buyer_phone, status, review_reason, invoice_id)
                is not distinct from (pg_temp.ph('twin'), 'needs_review', '2 customers share the buyer''s phone, so the customer must be chosen', null::uuid)
           from pg_temp.ord('D'))
    and pg_temp.audits('D') = 0
    and (pg_temp.tx('r6_after')::jsonb ->> 'invoices') = (pg_temp.tx('r6_before')::jsonb ->> 'invoices'),
  'R6 a waiting order keeps the phone the payment gave, whatever the registration says, and is not matched again');
select pg_temp.check((pg_temp.tx('r6_e_paid')::jsonb ->> 'status') = 'invoiced'
    and (select (buyer_phone, customer_id) = (pg_temp.ph('e'), pg_temp.fx('e')) from pg_temp.ord('E'))
    and (pg_temp.inv('E')).customer_id = pg_temp.fx('e') and pg_temp.audits('E') = 0
    and (pg_temp.tx('r6_e')::jsonb ->> 'invoice_no') = (pg_temp.tx('r6_e_paid')::jsonb ->> 'invoice_no'),
  'R6 so does an invoiced one, whose invoice stays its customer''s');
do $$ declare r jsonb; begin
  -- A phone the payment gave that the phone policy cannot read; one customer
  -- has the registration's WhatsApp.
  r := public.web_order_paid(pg_temp.paid('F', '12345'));
  insert into tx values ('r6_f_paid', r::text);
  perform pg_temp.new_phone('f');
  perform pg_temp.customer('f', 'R403 Unreadable', pg_temp.ph('f'));
  insert into tx values ('r6_f_before', pg_temp.snap()::text);
  r := public.web_order_names(pg_temp.names('F', pg_temp.ph('f')));
  insert into tx values ('r6_f', r::text);
end $$;
select pg_temp.check((pg_temp.tx('r6_f_paid')::jsonb ->> 'review_reason') = pg_temp.tx('no_phone')
    and (pg_temp.tx('r6_f')::jsonb ->> 'status') = 'needs_review'
    and (select (status, review_reason, buyer_phone, invoice_id, customer_id, buyer_first_name)
                is not distinct from ('needs_review', pg_temp.tx('no_phone'), '12345', null::uuid, null::uuid, 'Fixture')
           from pg_temp.ord('F'))
    and pg_temp.audits('F') = 0
    and (pg_temp.snap() ->> 'invoices') = (pg_temp.tx('r6_f_before')::jsonb ->> 'invoices')
    and (pg_temp.snap() ->> 'customers') = (pg_temp.tx('r6_f_before')::jsonb ->> 'customers'),
  'R6 even a payment phone the phone policy cannot read is kept: the names are kept, no audit row, no invoice, and the order waits for staff');

-- ═════ R7 Record-only and off channels keep the phone only ═════
update public.web_order_channels set mode = 'record_only' where key = pg_temp.tx('channel');
do $$ declare r jsonb; begin
  r := public.web_order_paid(pg_temp.paid('G', null));
  insert into tx values ('r7_paid', r::text);
  r := public.web_order_names(pg_temp.names('G', pg_temp.ph('one')));
  insert into tx values ('r7', r::text);
end $$;
select pg_temp.check((pg_temp.tx('r7_paid')::jsonb ->> 'status') = 'recorded'
    and (pg_temp.tx('r7')::jsonb ->> 'status') = 'recorded'
    and (select (status, buyer_phone, invoice_id) is not distinct from ('recorded', pg_temp.ph('one'), null::uuid) from pg_temp.ord('G'))
    and pg_temp.audits('G') = 1,
  'R7 a record-only channel keeps the WhatsApp (audited) and makes no invoice');
-- An order that waits for its phone on a channel switched off since.
update public.web_order_channels set mode = 'live' where key = pg_temp.tx('channel');
do $$ begin perform public.web_order_paid(pg_temp.paid('H', null)); end $$;
update public.web_order_channels set mode = 'off' where key = pg_temp.tx('channel');
do $$ declare r jsonb; begin
  r := public.web_order_names(pg_temp.names('H', pg_temp.ph('one')));
  insert into tx values ('r7_off', r::text);
end $$;
select pg_temp.check((select (status, review_reason, buyer_phone, invoice_id) is not distinct from ('needs_review', pg_temp.tx('no_phone'), pg_temp.ph('one'), null::uuid)
                        from pg_temp.ord('H')) and pg_temp.audits('H') = 1,
  'R7 an off channel keeps the WhatsApp too, and matches nothing');
update public.web_order_channels set mode = 'record_only' where key = pg_temp.tx('channel');
select pg_temp.as_user('manager');
do $$ declare r jsonb; begin
  r := public.web_order_resolve((pg_temp.ord('G')).id, null, false);
  insert into tx values ('r7_auto', r::text);
end $$;
select pg_temp.check((pg_temp.tx('r7_auto')::jsonb ->> 'status') = 'invoiced' and (pg_temp.inv('G')).customer_id = pg_temp.fx('one'),
  'R7 a Manager''s Match automatically then finds the customer by the kept WhatsApp');
update public.web_order_channels set mode = 'live' where key = pg_temp.tx('channel');

-- ═════ R8 Waiting for another reason ═════
select pg_temp.as_service();
do $$ declare r jsonb; begin
  -- Paid more than 2 hours after its checkout opened: a time rule (373).
  r := public.web_order_paid(pg_temp.paid('J', null, 1, true, now() - interval '3 hours'));
  insert into tx values ('r8_paid', r::text);
  insert into tx values ('r8_before', pg_temp.snap()::text);
  r := public.web_order_names(pg_temp.names('J', pg_temp.ph('one')));
  insert into tx values ('r8', r::text);
end $$;
select pg_temp.check((pg_temp.tx('r8_paid')::jsonb ->> 'review_reason')
                       = 'It was paid more than 2 hours after the checkout opened. Check the payment in HitPay before creating its invoice'
    and (select (status, review_reason, buyer_phone, invoice_id)
                is not distinct from ('needs_review', pg_temp.tx('r8_paid')::jsonb ->> 'review_reason', pg_temp.ph('one'), null::uuid) from pg_temp.ord('J'))
    and (pg_temp.snap() ->> 'invoices') = (pg_temp.tx('r8_before')::jsonb ->> 'invoices'),
  'R8 an order waiting for a time rule takes the WhatsApp but is not matched again');
select pg_temp.as_user('manager');
do $$ declare r jsonb; begin
  r := public.web_order_resolve((pg_temp.ord('J')).id, null, false);
  insert into tx values ('r8_auto', r::text);
end $$;
select pg_temp.check((pg_temp.tx('r8_auto')::jsonb ->> 'status') = 'invoiced' and (pg_temp.inv('J')).customer_id = pg_temp.fx('one'),
  'R8 a Manager who has seen the time reason creates it, matched by the WhatsApp');
-- Registered more than 7 days after a payment that passed every time rule:
-- the order's times moved back 8 days together, as if the days had passed.
select pg_temp.as_service();
do $$ declare r jsonb; begin
  r := public.web_order_paid(pg_temp.paid('V', null));
  insert into tx values ('r8_late_paid', r::text);
end $$;
update public.web_orders
   set paid_at = paid_at - interval '8 days', created_at = created_at - interval '8 days',
       checkout_opened_at = checkout_opened_at - interval '8 days'
 where stripe_session_id = pg_temp.hp('V');
do $$ declare r jsonb; begin
  insert into tx values ('r8_late_before', pg_temp.snap()::text);
  r := public.web_order_names(pg_temp.names('V', pg_temp.ph('one')));
  insert into tx values ('r8_late', r::text);
end $$;
insert into tx values ('seven_days', 'It was paid more than 7 days ago. Check the payment in HitPay before creating its invoice');
select pg_temp.check((pg_temp.tx('r8_late_paid')::jsonb ->> 'review_reason') = pg_temp.tx('no_phone')
    and (pg_temp.tx('r8_late')::jsonb ->> 'review_reason') = pg_temp.tx('seven_days')
    and (select (status, review_reason, buyer_phone, invoice_id)
                is not distinct from ('needs_review', pg_temp.tx('seven_days'), pg_temp.ph('one'), null::uuid) from pg_temp.ord('V'))
    and pg_temp.audits('V') = 1
    and (pg_temp.snap() ->> 'invoices') = (pg_temp.tx('r8_late_before')::jsonb ->> 'invoices'),
  'R8 one registered more than 7 days after its payment takes the WhatsApp and waits for a Manager to check the payment (373, judged now)');
select pg_temp.as_user('manager');
do $$ declare r jsonb; begin
  r := public.web_order_resolve((pg_temp.ord('V')).id, null, false);
  insert into tx values ('r8_late_auto', r::text);
end $$;
select pg_temp.check((pg_temp.tx('r8_late_auto')::jsonb ->> 'status') = 'invoiced' and (pg_temp.inv('V')).customer_id = pg_temp.fx('one'),
  'R8 the Manager who has seen it creates it, matched by the WhatsApp');
-- Waiting because its pass is not linked to a ticket (checked before the
-- customer), and linked before the names come: matching again would now
-- invoice it, so this shows it is not matched again.
select pg_temp.as_service();
do $$ declare r jsonb; begin
  r := public.web_order_paid(pg_temp.paid('U', null) || jsonb_build_object('ticket', 'day2'));
  insert into tx values ('r8_pass_paid', r::text);
end $$;
update public.web_order_channels
   set ticket_map = ticket_map || jsonb_build_object('day2', jsonb_build_object('option_id', pg_temp.fx('day1'),
                                                                                 'days', jsonb_build_array(pg_temp.d(7))))
 where key = pg_temp.tx('channel');
do $$ declare r jsonb; begin
  r := public.web_order_names(pg_temp.names('U', pg_temp.ph('one')));
  insert into tx values ('r8_pass', r::text);
end $$;
select pg_temp.check((pg_temp.tx('r8_pass_paid')::jsonb ->> 'review_reason') = 'The website pass "day2" is not linked to a ticket of the event'
    and (pg_temp.tx('r8_pass')::jsonb ->> 'status') = 'needs_review'
    and (select (status, review_reason, buyer_phone, invoice_id)
                is not distinct from ('needs_review', 'The website pass "day2" is not linked to a ticket of the event', pg_temp.ph('one'), null::uuid)
           from pg_temp.ord('U')),
  'R8 nor is one waiting because its pass was not linked, even once it is: it keeps the WhatsApp for staff');
-- A HitPay sandbox payment, kept while the channel accepted test orders.
select pg_temp.as_service();
update public.web_order_channels set allow_test = true where key = pg_temp.tx('channel');
do $$ declare r jsonb; begin
  r := public.web_order_paid(pg_temp.paid('K', null, 1, false));
  insert into tx values ('r8_test_paid', r::text);
end $$;
update public.web_order_channels set allow_test = false where key = pg_temp.tx('channel');
do $$ declare r jsonb; begin
  r := public.web_order_names(pg_temp.names('K', pg_temp.ph('one'), 1, false));
  insert into tx values ('r8_test', r::text);
end $$;
select pg_temp.check((pg_temp.tx('r8_test_paid')::jsonb ->> 'review_reason') = pg_temp.tx('no_phone')
    and (select (status, review_reason, buyer_phone, invoice_id) is not distinct from ('needs_review', pg_temp.tx('no_phone'), pg_temp.ph('one'), null::uuid)
           from pg_temp.ord('K')),
  'R8 a test payment the channel no longer accepts keeps the WhatsApp, and is neither matched again nor refused by the names');

-- ═════ R9 Refused and invoiced orders ═════
do $$ declare r jsonb; begin
  -- Refused at payment: a sandbox payment the channel does not accept.
  r := public.web_order_paid(pg_temp.paid('L', null, 1, false));
  insert into tx values ('r9_l_paid', r::text);
  r := public.web_order_names(pg_temp.names('L', pg_temp.ph('one'), 1, false));
  insert into tx values ('r9_l', r::text);
  -- Waiting for its phone, then invoiced by staff for a customer they found.
  perform public.web_order_paid(pg_temp.paid('M', null, 2));
  perform pg_temp.as_user('manager');
  perform pg_temp.customer('found', 'R403 Found', pg_temp.new_phone('found'));
  r := public.web_order_resolve((pg_temp.ord('M')).id, pg_temp.fx('found'), false);
  insert into tx values ('r9_m_resolved', r::text);
  perform pg_temp.as_service();
  insert into tx values ('r9_before', pg_temp.snap()::text);
  r := public.web_order_names(pg_temp.names('M', pg_temp.ph('one'), 2));
  insert into tx values ('r9_m', r::text);
end $$;
select pg_temp.check((pg_temp.tx('r9_l_paid')::jsonb ->> 'status') = 'refused'
    and (select (status, review_reason, buyer_phone, invoice_id) is not distinct from ('refused', 'A HitPay test payment', null::text, null::uuid)
           from pg_temp.ord('L'))
    and pg_temp.audits('L') = 0,
  'R9 a refused order takes no phone and stays refused');
select pg_temp.check((pg_temp.tx('r9_m_resolved')::jsonb ->> 'status') = 'invoiced'
    and (pg_temp.tx('r9_m')::jsonb ->> 'status') = 'invoiced'
    and (select (buyer_phone, customer_id) is not distinct from (null::text, pg_temp.fx('found')) from pg_temp.ord('M'))
    and (pg_temp.inv('M')).customer_id = pg_temp.fx('found') and pg_temp.audits('M') = 0
    and (pg_temp.snap() ->> 'invoices') = (pg_temp.tx('r9_before')::jsonb ->> 'invoices')
    and pg_temp.guests('M') = 'Fixture Buyer M / - / the buyer | Fixture Guest M-2 / - / -',
  'R9 an order staff invoiced takes no phone and keeps its customer; its names still go on its ticket: ' || coalesce(pg_temp.guests('M'), '-'));

-- ═════ R11 Names before the payment ═════
do $$ declare r jsonb; begin
  r := public.web_order_names(pg_temp.names('N', pg_temp.ph('one')));
  insert into tx values ('r11_early', r::text);
  insert into tx values ('r11_kept', (select count(*) from public.web_orders where stripe_session_id = pg_temp.hp('N'))::text);
  r := public.web_order_paid(pg_temp.paid('N', null));
  insert into tx values ('r11_paid', r::text);
  r := public.web_order_names(pg_temp.names('N', pg_temp.ph('one')));
  insert into tx values ('r11', r::text);
end $$;
select pg_temp.check((pg_temp.tx('r11_early')::jsonb ->> 'status') = 'not_found' and pg_temp.tx('r11_kept') = '0'
    and (pg_temp.tx('r11_paid')::jsonb ->> 'review_reason') = pg_temp.tx('no_phone')
    and (pg_temp.tx('r11')::jsonb ->> 'status') = 'invoiced' and (pg_temp.inv('N')).customer_id = pg_temp.fx('one'),
  'R11 names before the payment keep nothing; sent again after it, the order is matched by the WhatsApp');

-- ═════ R12 A passing fault while matching again ═════
insert into tx values ('uuid_def', pg_get_functiondef('public.web_order_uuid(text)'::regprocedure));
do $$ begin perform public.web_order_paid(pg_temp.paid('P', null)); end $$;
-- The payment's request id is taken last, so the fault comes after the
-- customer and the invoice are made.
create or replace function public.web_order_uuid(p_text text) returns uuid language plpgsql as
$f$begin raise exception 'R403: a passing fault' using errcode = '40001'; end$f$;
do $$ declare r jsonb; begin
  perform pg_temp.new_phone('p');
  insert into tx values ('r12_before', pg_temp.snap()::text);
  r := public.web_order_names(pg_temp.names('P', pg_temp.ph('p')));
  insert into tx values ('r12_fault', r::text);
  insert into tx values ('r12_fault_snap', pg_temp.snap()::text);
end $$;
do $$ begin execute pg_temp.tx('uuid_def'); end $$;
insert into tx values ('fault', 'The invoice could not be made when the buyer''s WhatsApp came with the registration, so it must be created');
select pg_temp.check(pg_temp.tx('r12_fault')::jsonb = jsonb_build_object('status', 'needs_review', 'invoice_no', null,
                       'review_reason', pg_temp.tx('fault'))
    and (select (status, review_reason, buyer_phone, buyer_first_name, invoice_id)
                is not distinct from ('needs_review', pg_temp.tx('fault'), pg_temp.ph('p'), 'Fixture', null::uuid) from pg_temp.ord('P'))
    and pg_temp.audits('P') = 1
    and (pg_temp.tx('r12_fault_snap')::jsonb ->> 'invoices') = (pg_temp.tx('r12_before')::jsonb ->> 'invoices')
    and (pg_temp.tx('r12_fault_snap')::jsonb ->> 'customers') = (pg_temp.tx('r12_before')::jsonb ->> 'customers'),
  'R12 a passing fault while matching again keeps the names and the phone (audited), leaves no invoice or customer, '
  || 'and the order waits for staff with a reason that says the invoice must be created');
select pg_temp.as_user('manager');
do $$ declare r jsonb; begin
  r := public.web_order_resolve((pg_temp.ord('P')).id, null, false);
  insert into tx values ('r12', r::text);
end $$;
select pg_temp.check((pg_temp.tx('r12')::jsonb ->> 'status') = 'invoiced'
    and (select (buyer_phone, status) = (pg_temp.ph('p'), 'invoiced') from pg_temp.ord('P'))
    and (select c.phone = public.normalize_customer_phone(pg_temp.ph('p')) from public.customers c where c.id = (pg_temp.inv('P')).customer_id),
  'R12 a Manager''s Match automatically then makes the invoice by the WhatsApp');
select pg_temp.as_service();

-- ═════ R13 Staff-link orders ═════
do $$ declare r jsonb; v_off text := 'OFF-' || to_char(public.sg_today(), 'YYYYMMDD') || '-' || upper(substr(md5(pg_temp.tx('sfx') || 'Q'), 1, 6)); begin
  insert into tx values ('off', v_off);
  r := public.web_order_door(jsonb_build_object('channel', pg_temp.tx('channel'), 'provider', 'door', 'order_id', v_off,
         'ticket', 'day1', 'quantity', 1, 'amount_total_cents', 6100, 'paid_on', public.sg_today()::text, 'method', 'cash',
         'reference', null, 'staff_id', null, 'registered_at', now(),
         'buyer', jsonb_build_object('first_name', 'Fixture', 'last_name', 'Door', 'email', null, 'whatsapp', null),
         'attendees', jsonb_build_array(jsonb_build_object('name', 'Fixture Door', 'email', null, 'whatsapp', null))));
  insert into tx values ('r13_door', r::text);
  insert into tx values ('r13_before', (select row(w.*)::text from public.web_orders w where w.stripe_session_id = v_off));
  r := public.web_order_names(pg_temp.names('Q', pg_temp.ph('one'), 1, true, v_off));
  insert into tx values ('r13', r::text);
end $$;
select pg_temp.check((pg_temp.tx('r13')::jsonb ->> 'status') = 'not_found'
    and (select row(w.*)::text from public.web_orders w where w.stripe_session_id = pg_temp.tx('off')) = pg_temp.tx('r13_before')
    and (select buyer_phone is null from public.web_orders where stripe_session_id = pg_temp.tx('off')),
  'R13 a staff-link order is not reached by a names message: it keeps no phone and changes nothing');

-- ═════ R14 Staff choose any customer ═════
select pg_temp.as_service();
do $$ begin
  perform public.web_order_paid(pg_temp.paid('S', pg_temp.ph('twin')));   -- waits with the twins as candidates
  perform public.web_order_paid(pg_temp.paid('T', null));                 -- waits for its phone
end $$;
select pg_temp.as_user('manager');
do $$ declare r jsonb; begin
  perform pg_temp.customer('other', 'R403 Other', pg_temp.new_phone('other'));
  r := public.web_order_resolve((pg_temp.ord('S')).id, pg_temp.fx('other'), false);
  insert into tx values ('r14_s', r::text);
  r := public.web_order_resolve((pg_temp.ord('T')).id, null, true);
  insert into tx values ('r14_t_new', r::text);
  r := public.web_order_resolve((pg_temp.ord('T')).id, null, false);
  insert into tx values ('r14_t_auto', r::text);
  insert into tx values ('r14_list', public.web_orders_list(pg_temp.fx('ev'))::text);
  r := public.web_order_resolve((pg_temp.ord('T')).id, pg_temp.fx('other'), false);
  insert into tx values ('r14_t', r::text);
end $$;
select pg_temp.check((pg_temp.tx('r14_s')::jsonb ->> 'status') = 'invoiced'
    and (pg_temp.inv('S')).customer_id = pg_temp.fx('other') and (pg_temp.ord('S')).customer_id = pg_temp.fx('other')
    and exists (select 1 from public.audit_logs a where a.record_id = (pg_temp.ord('S')).id and a.action = 'web_order_resolved'
                  and (a.new_data ->> 'customer_id')::uuid = pg_temp.fx('other') and a.changed_by = pg_temp.fx('manager')),
  'R14 a Manager invoices a waiting order for a customer they found who is not a candidate (audited)');
select pg_temp.check((pg_temp.tx('r14_t_new')::jsonb ->> 'review_reason') = pg_temp.tx('no_phone')
    and (pg_temp.tx('r14_t_auto')::jsonb ->> 'review_reason') = pg_temp.tx('no_phone'),
  'R14 with no phone, a new customer or Match automatically still cannot be made: the phone reason again');
select pg_temp.check((pg_temp.tx('r14_t')::jsonb ->> 'status') = 'invoiced' and (pg_temp.inv('T')).customer_id = pg_temp.fx('other'),
  'R14 a no-phone order is invoiced for a customer staff found');

-- ═════ R15 What the list says ═════
create function pg_temp.listed(list text, tag text) returns jsonb language sql as
$$ select x from jsonb_array_elements(pg_temp.tx(list)::jsonb -> 'orders') x where x->>'stripe_session_id' = pg_temp.hp(tag) $$;
select pg_temp.as_user('manager');
insert into tx values ('r15_list', public.web_orders_list(pg_temp.fx('ev'))::text);
select pg_temp.check((select (x->>'buyer_name', x->>'buyer_first_name', x->>'buyer_last_name', x->>'buyer_phone',
                              (x->>'buyer_phone_readable')::boolean, (x->>'buyer_phone_from_registration')::boolean)
                             = ('Website buyer', 'Fixture', 'Buyer A', pg_temp.ph('one'), true, true)
                        from pg_temp.listed('r15_list', 'A') x),
  'R15 an order whose phone came from the registration says so, with the registered name parts');
select pg_temp.check((select ((x->>'buyer_phone_readable')::boolean, (x->>'buyer_phone_from_registration')::boolean) = (true, false)
                        from pg_temp.listed('r15_list', 'E') x)
    and (select ((x->>'buyer_phone_readable')::boolean, (x->>'buyer_phone_from_registration')::boolean, x->>'buyer_first_name')
                is not distinct from (false, false, null::text)
           from pg_temp.listed('r14_list', 'T') x)
    and (select ((x->>'buyer_phone_readable')::boolean, x->>'buyer_phone') is not distinct from (false, null::text)
           from pg_temp.listed('r14_list', 'T') x)
    and (select ((x->>'buyer_phone_readable')::boolean, (x->>'buyer_phone_from_registration')::boolean, x->>'buyer_phone')
                is not distinct from (false, false, '12345')
           from pg_temp.listed('r15_list', 'F') x),
  'R15 a payment''s phone is not the registration''s; an order with no phone and no registration, or a payment phone '
  || 'that cannot be read, says it cannot be read');
select pg_temp.check((select count(*) from jsonb_array_elements(pg_temp.tx('r15_list')::jsonb -> 'orders')) =
                       (select count(*) from public.web_orders where channel = pg_temp.tx('channel'))
    and (select bool_and(x ? 'buyer_phone_readable' and x ? 'buyer_phone_from_registration' and x ? 'hand_invoices'
                         and x ? 'candidates' and x ? 'door_method')
           from jsonb_array_elements(pg_temp.tx('r15_list')::jsonb -> 'orders') x),
  'R15 every order is listed, with the new fields beside the old ones');
select pg_temp.as_user('staff');
select pg_temp.check(pg_temp.err(format('select public.web_orders_list(%L)', pg_temp.fx('ev')))
                       = 'Only an Owner, Admin or Manager can see website orders',
  'R15 staff still cannot see website orders');

-- ═════ R16 Held back by an invoice made by hand for the customer ═════
-- A ticket invoice made by hand at the event's store, as the current user:
-- one line of the option's tickets, one person each (a name, and a phone or
-- none).
create function pg_temp.hand(key text, cust uuid, opt uuid, day date, people jsonb) returns uuid language sql as
$$ with i as (select public.create_invoice_with_details(pg_temp.fx('van'), cust, jsonb_build_array(jsonb_build_object(
                'kind', 'event_ticket', 'event_ticket_option_id', opt, 'quantity', jsonb_array_length(people),
                'event_days', jsonb_build_array(day), 'attendees', people)),
                jsonb_build_object('business_date', pg_temp.d(0)::text)) as id)
   insert into fx select key, id from i returning v $$;
create function pg_temp.no(key text) returns text language sql as
$$ select invoice_no from public.invoices where id = pg_temp.fx(key) $$;
insert into tx values ('hold', 'The buyer''s WhatsApp from the registration is on a ticket invoice made by hand for this event: '
                               || 'use Link invoice if that invoice is this order''s, otherwise Create invoice');
select pg_temp.as_user('owner');
do $$ begin
  perform pg_temp.customer('h16', 'R403 Hand Buyer', pg_temp.new_phone('h16'));
  perform pg_temp.hand('inv16', pg_temp.fx('h16'), pg_temp.fx('day1'), pg_temp.d(7),
                       jsonb_build_array(jsonb_build_object('name', 'Fixture Hand Sixteen')));
end $$;
select pg_temp.as_service();
do $$ declare r jsonb; begin
  r := public.web_order_paid(pg_temp.paid('W', null));
  insert into tx values ('r16_paid', r::text), ('r16_before', pg_temp.snap()::text);
  r := public.web_order_names(pg_temp.names('W', pg_temp.ph('h16')));
  insert into tx values ('r16', r::text), ('r16_after', pg_temp.snap()::text);
  r := public.web_order_names(pg_temp.names('W', pg_temp.ph('h16')));
  insert into tx values ('r16_again', r::text);
  -- The payment delivered again, and a later registration whose WhatsApp
  -- one customer has and no invoice made by hand.
  r := public.web_order_paid(pg_temp.paid('W', null));
  insert into tx values ('r16_repaid', r::text);
  r := public.web_order_names(pg_temp.names('W', pg_temp.ph('one')));
  insert into tx values ('r16_other', r::text), ('r16_last', pg_temp.snap()::text);
end $$;
select pg_temp.check((pg_temp.tx('r16_paid')::jsonb ->> 'review_reason') = pg_temp.tx('no_phone')
    and pg_temp.tx('r16')::jsonb = jsonb_build_object('status', 'needs_review', 'invoice_no', null, 'review_reason', pg_temp.tx('hold')),
  'R16 a registration''s WhatsApp on the customer of a ticket invoice made by hand for the event holds the order: '
  || 'the answer is a waiting order''s, with the reason: ' || pg_temp.tx('r16'));
select pg_temp.check((select (status, review_reason, buyer_phone, invoice_id, customer_id, customer_created, candidate_customer_ids,
                              buyer_first_name, buyer_last_name, attendees -> 0 ->> 'name', names_at is not null)
                             is not distinct from ('needs_review', pg_temp.tx('hold'), pg_temp.ph('h16'), null::uuid, null::uuid, false,
                                                   array[pg_temp.fx('h16')], 'Fixture', 'Buyer W', 'Fixture Buyer W', true)
                        from pg_temp.ord('W'))
    and pg_temp.audits('W') = 1,
  'R16 it waits in Needs review with that reason and the customer with the phone as its candidate; the names, the phone and its audit row are kept');
select pg_temp.check((pg_temp.tx('r16_after')::jsonb - 'orders' - 'audits') = (pg_temp.tx('r16_before')::jsonb - 'orders' - 'audits')
    and (pg_temp.tx('r16_after')::jsonb ->> 'audits')::int = (pg_temp.tx('r16_before')::jsonb ->> 'audits')::int + 1
    and (select count(*) from public.web_orders w where w.invoice_id = pg_temp.fx('inv16')) = 0,
  'R16 nothing is made (no invoice, payment, customer or guest), and the invoice made by hand is no order''s yet');
select pg_temp.check(pg_temp.tx('r16_again')::jsonb = pg_temp.tx('r16')::jsonb,
  'R16 the same names again answer the same');
select pg_temp.check(pg_temp.tx('r16_repaid')::jsonb = pg_temp.tx('r16')::jsonb and pg_temp.tx('r16_other')::jsonb = pg_temp.tx('r16')::jsonb
    and pg_temp.tx('r16_last')::jsonb = pg_temp.tx('r16_after')::jsonb and pg_temp.audits('W') = 1,
  'R16 nothing gets past the hold: the names again, the payment delivered again, or a later registration with another '
  || 'WhatsApp answer the same and change nothing');

-- ═════ R17 Held back by a guest's phone on an invoice made by hand ═════
select pg_temp.as_user('owner');
do $$ begin
  perform pg_temp.customer('c17', 'R403 Hand Payer', pg_temp.new_phone('c17'));
  perform pg_temp.new_phone('g17');   -- no customer has it
  perform pg_temp.hand('inv17', pg_temp.fx('c17'), pg_temp.fx('day1'), pg_temp.d(7),
                       jsonb_build_array(jsonb_build_object('name', 'Fixture Hand Payer'),
                                         jsonb_build_object('name', 'Fixture Hand Guest', 'phone', pg_temp.ph('g17'))));
end $$;
select pg_temp.as_service();
do $$ declare r jsonb; begin
  perform public.web_order_paid(pg_temp.paid('X', null));
  insert into tx values ('r17_before', pg_temp.snap()::text);
  r := public.web_order_names(pg_temp.names('X', pg_temp.ph('g17')));
  insert into tx values ('r17', r::text), ('r17_after', pg_temp.snap()::text);
end $$;
select pg_temp.check(pg_temp.tx('r17')::jsonb = jsonb_build_object('status', 'needs_review', 'invoice_no', null, 'review_reason', pg_temp.tx('hold'))
    and (select (status, review_reason, buyer_phone, invoice_id, candidate_customer_ids)
                is not distinct from ('needs_review', pg_temp.tx('hold'), pg_temp.ph('g17'), null::uuid, '{}'::uuid[])
           from pg_temp.ord('X'))
    and pg_temp.audits('X') = 1
    and (pg_temp.tx('r17_after')::jsonb - 'orders' - 'audits') = (pg_temp.tx('r17_before')::jsonb - 'orders' - 'audits'),
  'R17 a guest''s phone on the invoice made by hand holds it too: it waits with the reason and no candidates, and no customer is made for the WhatsApp');

-- ═════ R18 Invoices made by hand that do not hold ═════
select pg_temp.as_user('owner');
do $$ declare v uuid; ev2 uuid; begin
  -- Cancelled.
  perform pg_temp.customer('c18', 'R403 Cancelled Hand', pg_temp.new_phone('c18'));
  v := pg_temp.hand('inv18c', pg_temp.fx('c18'), pg_temp.fx('day1'), pg_temp.d(7), jsonb_build_array(jsonb_build_object('name', 'Fixture Cancelled')));
  perform public.cancel_invoice_recorded(v, 'R403 cancel', gen_random_uuid());
  -- Refunded.
  perform pg_temp.customer('r18', 'R403 Refunded Hand', pg_temp.new_phone('r18'));
  v := pg_temp.hand('inv18r', pg_temp.fx('r18'), pg_temp.fx('day1'), pg_temp.d(7), jsonb_build_array(jsonb_build_object('name', 'Fixture Refunded')));
  update public.invoices set status = 'refunded' where id = v;
  -- Linked to another website order (Y0, below).
  perform pg_temp.customer('l18', 'R403 Linked Hand', pg_temp.new_phone('l18'));
  perform pg_temp.hand('inv18l', pg_temp.fx('l18'), pg_temp.fx('day1'), pg_temp.d(7), jsonb_build_array(jsonb_build_object('name', 'Fixture Linked')));
  -- For another event at the same store.
  ev2 := public.event_save(jsonb_build_object('name', 'R403 Other Seminar ' || pg_temp.tx('sfx'),
    'days', jsonb_build_array(jsonb_build_object('day', pg_temp.d(9))), 'store_ids', jsonb_build_array(pg_temp.fx('van')),
    'options', jsonb_build_array(jsonb_build_object('name', '1 Day', 'days_count', 1, 'price', 61))));
  insert into fx values ('ev2', ev2), ('ev2_day', (select id from public.event_ticket_options where event_id = ev2 and name = '1 Day'));
  perform pg_temp.customer('e18', 'R403 Other Event', pg_temp.new_phone('e18'));
  perform pg_temp.hand('inv18e', pg_temp.fx('e18'), pg_temp.fx('ev2_day'), pg_temp.d(9), jsonb_build_array(jsonb_build_object('name', 'Fixture Other Event')));
end $$;
select pg_temp.as_service();
do $$ begin
  perform public.web_order_paid(pg_temp.paid(t, null)) from unnest(array['Y0', 'Y1', 'Y2', 'Y3', 'Y4']) t;
end $$;
select pg_temp.as_user('manager');
do $$ declare r jsonb; begin
  r := public.web_order_link_invoice((pg_temp.ord('Y0')).id, pg_temp.no('inv18l'));
  insert into tx values ('r18_link', r::text);
end $$;
select pg_temp.as_service();
do $$ declare r jsonb; begin
  r := public.web_order_names(pg_temp.names('Y1', pg_temp.ph('c18')));
  insert into tx values ('r18_1', r::text);
  r := public.web_order_names(pg_temp.names('Y2', pg_temp.ph('r18')));
  insert into tx values ('r18_2', r::text);
  r := public.web_order_names(pg_temp.names('Y3', pg_temp.ph('l18')));
  insert into tx values ('r18_3', r::text);
  r := public.web_order_names(pg_temp.names('Y4', pg_temp.ph('e18')));
  insert into tx values ('r18_4', r::text);
end $$;
create function pg_temp.invoiced_anew(tag text, cust text, hand text) returns boolean language sql as
$$ select (pg_temp.ord(tag)).status = 'invoiced' and (pg_temp.inv(tag)).customer_id = pg_temp.fx(cust)
          and (pg_temp.inv(tag)).id <> pg_temp.fx(hand) and (pg_temp.inv(tag)).status = 'paid' and pg_temp.audits(tag) = 1 $$;
select pg_temp.check((select status from public.invoices where id = pg_temp.fx('inv18c')) = 'cancelled'
    and (pg_temp.tx('r18_1')::jsonb ->> 'status') = 'invoiced' and pg_temp.invoiced_anew('Y1', 'c18', 'inv18c'),
  'R18 a cancelled invoice made by hand does not hold: the order is invoiced for the customer with the WhatsApp');
select pg_temp.check((select status from public.invoices where id = pg_temp.fx('inv18r')) = 'refunded'
    and (pg_temp.tx('r18_2')::jsonb ->> 'status') = 'invoiced' and pg_temp.invoiced_anew('Y2', 'r18', 'inv18r'),
  'R18 nor does a refunded one');
select pg_temp.check((pg_temp.tx('r18_link')::jsonb ->> 'status') = 'invoiced' and (pg_temp.ord('Y0')).invoice_id = pg_temp.fx('inv18l')
    and (pg_temp.tx('r18_3')::jsonb ->> 'status') = 'invoiced' and pg_temp.invoiced_anew('Y3', 'l18', 'inv18l'),
  'R18 nor one linked to another website order');
select pg_temp.check((pg_temp.tx('r18_4')::jsonb ->> 'status') = 'invoiced' and pg_temp.invoiced_anew('Y4', 'e18', 'inv18e'),
  'R18 nor one for another event');

-- ═════ R19 After the hold: the hint, Link invoice and Create invoice ═════
select pg_temp.as_user('manager');
insert into tx values ('r19_list', public.web_orders_list(pg_temp.fx('ev'))::text);
select pg_temp.check((select (x->>'status', x->>'review_reason', x->'hand_invoices', (x->>'buyer_phone_readable')::boolean,
                              (x->>'buyer_phone_from_registration')::boolean)
                             = ('needs_review', pg_temp.tx('hold'),
                                jsonb_build_array(jsonb_build_object('invoice_no', pg_temp.no('inv16'), 'store', 'R403 Van ' || pg_temp.tx('sfx'))),
                                true, true)
                        from pg_temp.listed('r19_list', 'W') x)
    and (select x->'hand_invoices' = jsonb_build_array(jsonb_build_object('invoice_no', pg_temp.no('inv17'), 'store', 'R403 Van ' || pg_temp.tx('sfx')))
           from pg_temp.listed('r19_list', 'X') x),
  'R19 the list gives a held order''s Manager the invoice made by hand by number (the page''s "Possibly already invoiced by hand" hint), '
  || 'its reason, and a phone from the registration that can be read');
-- What each refuses is kept as the answer, so the checks still run.
do $$ declare r jsonb; begin
  insert into tx values ('r19_before', pg_temp.snap()::text);
  begin r := public.web_order_link_invoice((pg_temp.ord('W')).id, pg_temp.no('inv16'));
  exception when others then r := jsonb_build_object('error', sqlerrm); end;
  insert into tx values ('r19_link', r::text), ('r19_link_snap', pg_temp.snap()::text);
  begin r := public.web_order_resolve((pg_temp.ord('X')).id, null, false);
  exception when others then r := jsonb_build_object('error', sqlerrm); end;
  insert into tx values ('r19_auto', r::text);
  insert into tx values ('r19_list2', public.web_orders_list(pg_temp.fx('ev'))::text);
end $$;
select pg_temp.check(pg_temp.tx('r19_link')::jsonb = jsonb_build_object('status', 'invoiced', 'invoice_no', pg_temp.no('inv16'))
    and (select (status, invoice_id, customer_id, review_reason, candidate_customer_ids)
                is not distinct from ('invoiced', pg_temp.fx('inv16'), pg_temp.fx('h16'), null::text, '{}'::uuid[])
           from pg_temp.ord('W'))
    and (pg_temp.tx('r19_link_snap')::jsonb ->> 'invoices') = (pg_temp.tx('r19_before')::jsonb ->> 'invoices')
    and (pg_temp.tx('r19_link_snap')::jsonb ->> 'customers') = (pg_temp.tx('r19_before')::jsonb ->> 'customers')
    and (select x->'hand_invoices' from pg_temp.listed('r19_list2', 'W') x) = '[]'::jsonb,
  'R19 Link invoice links a held order to the invoice made by hand, making nothing, and the hint is gone: ' || pg_temp.tx('r19_link'));
select pg_temp.check((pg_temp.tx('r19_auto')::jsonb ->> 'status') = 'invoiced'
    and (pg_temp.inv('X')).id <> pg_temp.fx('inv17') and (pg_temp.inv('X')).status = 'paid'
    and (select (c.phone, c.first_name, c.last_name) = (public.normalize_customer_phone(pg_temp.ph('g17')), 'Fixture', 'Buyer X')
           from public.customers c where c.id = (pg_temp.inv('X')).customer_id)
    and (pg_temp.ord('X')).customer_created,
  'R19 Create invoice (Match automatically) invoices a held order as another sale, by the WhatsApp (here a new customer with it): '
  || pg_temp.tx('r19_auto'));

-- ═════ R20 A recorded order on a live channel ═════
update public.web_order_channels set mode = 'record_only' where key = pg_temp.tx('channel');
select pg_temp.as_service();
do $$ begin
  perform public.web_order_paid(pg_temp.paid('Z1', null));
  perform public.web_order_paid(pg_temp.paid('Z2', null));
end $$;
update public.web_order_channels set mode = 'live' where key = pg_temp.tx('channel');
select pg_temp.as_user('owner');
do $$ begin
  perform pg_temp.customer('z20', 'R403 Recorded Hand', pg_temp.new_phone('z20'));
  perform pg_temp.hand('inv20', pg_temp.fx('z20'), pg_temp.fx('day1'), pg_temp.d(7), jsonb_build_array(jsonb_build_object('name', 'Fixture Recorded Hand')));
  perform pg_temp.customer('z20b', 'R403 Recorded', pg_temp.new_phone('z20b'));
end $$;
select pg_temp.as_service();
do $$ declare r jsonb; begin
  insert into tx values ('r20_before', pg_temp.snap()::text);
  r := public.web_order_names(pg_temp.names('Z1', pg_temp.ph('z20')));
  insert into tx values ('r20_1', r::text), ('r20_after', pg_temp.snap()::text);
  r := public.web_order_names(pg_temp.names('Z2', pg_temp.ph('z20b')));
  insert into tx values ('r20_2', r::text);
end $$;
select pg_temp.check((pg_temp.tx('r20_1')::jsonb ->> 'status') = 'invoiced'
    and (pg_temp.tx('r20_1')::jsonb ->> 'invoice_no') = (pg_temp.inv('Z1')).invoice_no
    and pg_temp.invoiced_anew('Z1', 'z20', 'inv20')
    and (pg_temp.ord('Z1')).buyer_phone = pg_temp.ph('z20')
    and (pg_temp.tx('r20_after')::jsonb ->> 'invoices')::int = (pg_temp.tx('r20_before')::jsonb ->> 'invoices')::int + 1,
  'R20 a recorded order on a live channel is not held: its first match, when its names come, invoices it by the WhatsApp '
  || 'as at payment, though an invoice made by hand has that phone');
select pg_temp.check((pg_temp.tx('r20_2')::jsonb ->> 'status') = 'invoiced' and (pg_temp.inv('Z2')).customer_id = pg_temp.fx('z20b')
    and pg_temp.audits('Z2') = 1,
  'R20 nor, without an invoice made by hand, is it held: it is invoiced by the WhatsApp as before');

do $$ declare v_failed int; begin
  select count(*) into v_failed from failed;
  if v_failed > 0 then raise exception '% check(s) failed: %', v_failed, (select string_agg(msg, '; ' order by n) from failed); end if;
  raise notice 'All registration phone checks passed.';
end $$;
rollback;
