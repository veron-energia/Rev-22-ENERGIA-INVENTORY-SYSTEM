-- 372_website_orders_become_invoices.sql
--
-- WEBSITE ORDERS BECOME INVOICES (asked for on 30 Sep 2026; the owner's rules)
--
--   An event's own website (the first: the Alaric Birthday Month site) sells
--   tickets through Stripe. When Stripe confirms a payment, the website sends
--   the order here through a signed Supabase edge function (web-ticket-order),
--   and the order becomes an invoice like one made at the counter:
--
--   1. The invoice is made at payment. The buyer is the first person on the
--      ticket; the others get placeholder names ("<buyer> · Guest 2") until the
--      buyer names them on the website, which renames them here.
--   2. It is raised by a chosen profile (the owner chose an Owner), at the
--      event's store, dated on the Singapore day the checkout was opened (the
--      website decided the early bird then; a checkout can be paid up to an hour
--      later). The ticket is priced by the event's own rules, and its total must
--      equal what Stripe charged, to the cent, or nothing is invoiced and the
--      order waits for review.
--   3. The payment is recorded with a chosen method (the owner chose a new
--      "Stripe (online)"), for the amount Stripe charged, with the Stripe payment
--      as its reference. The invoice is then paid like any other: commission,
--      guests and reports follow.
--   4. The buyer is matched by phone alone: one customer with that phone is the
--      buyer; none, and a new customer is made (with the channel's source);
--      two or more, and the order waits for staff to choose.
--   5. Nothing is ever invoiced twice: an order is keyed by its Stripe checkout,
--      and a repeated call returns the invoice already made.
--   6. A channel is off, record-only (orders are kept, no invoices) or live; it
--      starts record-only and only an Owner switches it. Stripe test orders are
--      refused unless the channel allows them.
--   7. Owners, Admins and Managers see an event's website orders and create the
--      invoice of one that waits (choosing the customer, or a new one).
--
--   Door sales (cash, PayNow) and Stripe refunds stay manual (the owner).
--
-- Only the service role (the edge function) can hand an order in. Nothing
-- existing is changed; one payment method is added.

set lock_timeout = '5s';

do $$ begin
  if to_regclass('public.events') is null then
    raise exception '372: apply 370 (events) first'; end if;
end $$;

-- ── 1. Where orders come from, and what they became ────────────────────────
insert into public.payment_methods (name, is_active)
select 'Stripe (online)', true
 where not exists (select 1 from public.payment_methods where lower(name) = lower('Stripe (online)'));

-- One row per website: which event and tickets its passes are, and how its
-- invoices are made. ticket_map: {"<website pass>": {"option_id": uuid, "days": [date, ...]}}.
create table if not exists public.web_order_channels (
  key               text primary key,
  event_id          uuid not null references public.events(id),
  ticket_map        jsonb not null,
  store_id          uuid not null references public.stores(id),
  acting_profile_id uuid not null references public.profiles(id),
  payment_method_id uuid not null references public.payment_methods(id),
  source_option_id  uuid references public.customer_source_options(id),
  source_details    text,
  mode              text not null default 'record_only',
  allow_test        boolean not null default false,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint web_order_channels_mode check (mode in ('off','record_only','live')),
  constraint web_order_channels_map check (jsonb_typeof(ticket_map) = 'object')
);

create table if not exists public.web_orders (
  id                     uuid primary key default gen_random_uuid(),
  channel                text not null references public.web_order_channels(key),
  stripe_session_id      text not null unique,
  stripe_payment_intent  text,
  livemode               boolean not null,
  status                 text not null,
  ticket                 text not null,
  quantity               integer not null,
  unit_amount_cents      integer not null,
  amount_total_cents     integer not null,
  early_bird             boolean not null,
  buyer_name             text not null,
  buyer_email            text,
  buyer_phone            text,
  checkout_opened_at     timestamptz not null,
  paid_at                timestamptz not null,
  attendees              jsonb,
  names_at               timestamptz,
  buyer_first_name       text,
  buyer_last_name        text,
  invoice_id             uuid references public.invoices(id) on delete set null,
  customer_id            uuid references public.customers(id) on delete set null,
  customer_created       boolean not null default false,
  review_reason          text,
  candidate_customer_ids uuid[] not null default '{}',
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  constraint web_orders_status check (status in ('recorded','invoiced','needs_review','refused')),
  constraint web_orders_quantity check (quantity between 1 and 10),
  constraint web_orders_amounts check (unit_amount_cents >= 0 and amount_total_cents >= 0),
  constraint web_orders_invoiced check (status <> 'invoiced' or invoice_id is not null)
);
create index if not exists web_orders_channel_idx on public.web_orders(channel, created_at desc);
create index if not exists web_orders_invoice_idx on public.web_orders(invoice_id) where invoice_id is not null;

alter table public.web_order_channels enable row level security;
alter table public.web_orders enable row level security;
revoke all on table public.web_order_channels, public.web_orders from anon, authenticated;
grant all on table public.web_order_channels, public.web_orders to service_role;

-- ── 2. The rules (internal) ────────────────────────────────────────────────

-- A uuid that is always the same for the same text: request ids that make a
-- repeated call a replay.
create or replace function public.web_order_uuid(p_text text)
returns uuid language sql immutable as $f$
  select (substr(md5(p_text), 1, 8) || '-' || substr(md5(p_text), 9, 4) || '-4' || substr(md5(p_text), 14, 3)
          || '-a' || substr(md5(p_text), 18, 3) || '-' || substr(md5(p_text), 21, 12))::uuid
$f$;

-- The customers who share a phone, most recently active first. Phones are
-- compared as the phone policy (161) reads them, so a number stored before it
-- in the local 8-digit form is the same phone as its international form.
create or replace function public.web_order_phone_customers(p_phone text)
returns uuid[] language sql stable security definer set search_path to 'public' as $f$
  select coalesce(array_agg(c.id order by coalesce((select max(i.created_at) from public.invoices i
                                                      where i.customer_id = c.id and i.deleted_at is null), c.created_at) desc, c.id), '{}')
    from public.customers c
   where c.deleted_at is null and p_phone is not null and public.normalize_customer_phone(c.phone) = p_phone
$f$;

-- The customer an order is for: the one chosen, a new one, or the one
-- customer with the buyer's phone (none: a new one; two or more: review).
-- Runs as the channel's acting profile.
create or replace function public.web_order_customer(p_order public.web_orders, p_channel public.web_order_channels,
  p_customer_id uuid, p_new_customer boolean)
returns uuid language plpgsql security definer set search_path to 'public' as $f$
declare v_phone text; v_ids uuid[]; v_res jsonb; v_id uuid;
begin
  if p_customer_id is not null then
    if not exists (select 1 from public.customers where id = p_customer_id and deleted_at is null) then
      raise exception 'WEB_ORDER_REVIEW: The chosen customer was not found'; end if;
    return p_customer_id;
  end if;
  v_phone := public.normalize_customer_phone(p_order.buyer_phone);
  if v_phone is null then
    raise exception 'WEB_ORDER_REVIEW: The buyer''s phone number could not be read, so the customer must be chosen'; end if;
  -- The same lock the other identity flows take (162), so they never make one
  -- phone's customer twice at once.
  perform pg_advisory_xact_lock(hashtextextended('customer-identity:' || v_phone, 0));
  if not p_new_customer then
    v_ids := public.web_order_phone_customers(v_phone);
    if cardinality(v_ids) = 1 then return v_ids[1]; end if;
    if cardinality(v_ids) > 1 then
      raise exception 'WEB_ORDER_REVIEW: % customers share the buyer''s phone, so the customer must be chosen', cardinality(v_ids); end if;
  end if;
  v_res := public.create_customer_quick(p_order.buyer_name, null, v_phone, p_order.buyer_email,
             p_request_id => public.web_order_uuid('web-order-customer:' || p_order.stripe_session_id));
  v_id := (v_res->>'customer_id')::uuid;
  if p_channel.source_option_id is not null and not coalesce((v_res->>'replayed')::boolean, false) then
    perform public.set_customer_source(v_id, p_channel.source_option_id, p_channel.source_details,
      'Website order ' || p_order.stripe_session_id);
  end if;
  update public.web_orders set customer_created = not coalesce((v_res->>'replayed')::boolean, false) or customer_created
   where id = p_order.id;
  return v_id;
end $f$;

-- The people on an order's ticket: the names the buyer gave, or the buyer and
-- placeholders. The first person is the buyer's customer.
create or replace function public.web_order_people(p_order public.web_orders, p_customer_id uuid)
returns jsonb language sql stable security definer set search_path to 'public' as $f$
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'name', case when a.x is not null and btrim(coalesce(a.x->>'name', '')) <> '' then btrim(a.x->>'name')
                        when k = 1 then p_order.buyer_name
                        else p_order.buyer_name || ' · Guest ' || k end,
           'phone', case when k = 1 then coalesce(nullif(btrim(a.x->>'whatsapp'), ''), p_order.buyer_phone)
                         else nullif(btrim(a.x->>'whatsapp'), '') end,
           'customer_id', case when k = 1 then p_customer_id end)) order by k)
    from generate_series(1, p_order.quantity) k
    left join lateral (select case when jsonb_typeof(p_order.attendees) = 'array' then p_order.attendees -> (k - 1) end as x) a on true
$f$;

-- Makes the invoice of an order and records its payment, as the channel's
-- acting profile. A business refusal leaves nothing behind and puts the order
-- in review with the reason; a passing fault (a lock, a clash on the invoice
-- number) is raised, so the caller tries again.
create or replace function public.web_order_make_invoice(p_order_id uuid, p_customer_id uuid default null,
  p_new_customer boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare
  o public.web_orders%rowtype; ch public.web_order_channels%rowtype; v_prev text;
  v_customer uuid; v_map jsonb; v_items jsonb; v_inv uuid; v_total numeric; v_paid date; v_reason text; v_state text;
begin
  select * into o from public.web_orders where id = p_order_id for update;
  if not found then raise exception 'Website order not found'; end if;
  if o.status = 'invoiced' then
    return jsonb_build_object('status', 'invoiced', 'invoice_no', (select invoice_no from public.invoices where id = o.invoice_id),
                              'review_reason', null);
  end if;
  select * into ch from public.web_order_channels where key = o.channel;
  -- A Stripe test payment is never invoiced unless the channel allows it now,
  -- whenever it was recorded.
  if not o.livemode and not ch.allow_test then
    update public.web_orders set status = 'refused', review_reason = 'A Stripe test payment', updated_at = now()
     where id = o.id;
    return jsonb_build_object('status', 'refused', 'invoice_no', null, 'review_reason', 'A Stripe test payment');
  end if;
  v_prev := current_setting('request.jwt.claim.sub', true);
  perform set_config('request.jwt.claim.sub', ch.acting_profile_id::text, true);
  begin
    if not exists (select 1 from public.profiles p where p.id = ch.acting_profile_id and p.is_active and p.deleted_at is null
                     and p.role in ('owner','admin','manager')) then
      raise exception 'WEB_ORDER_REVIEW: The profile that raises website invoices is not an active Owner, Admin or Manager'; end if;
    v_map := ch.ticket_map -> o.ticket;
    if v_map is null or nullif(v_map->>'option_id', '') is null then
      raise exception 'WEB_ORDER_REVIEW: The website pass "%" is not linked to a ticket of the event', o.ticket; end if;
    v_customer := public.web_order_customer(o, ch, p_customer_id, p_new_customer);
    v_items := jsonb_build_array(jsonb_build_object(
      'kind', 'event_ticket', 'event_ticket_option_id', v_map->>'option_id', 'quantity', o.quantity,
      'event_days', coalesce(v_map->'days', '[]'::jsonb),
      'attendees', public.web_order_people(o, v_customer)));
    v_inv := public.create_invoice_with_details(ch.store_id, v_customer, v_items, jsonb_build_object(
      'business_date', ((o.checkout_opened_at at time zone 'Asia/Singapore')::date)::text,
      'notes', 'Website order · Stripe ' || o.stripe_session_id || case when o.early_bird then ' · early bird' else '' end,
      'manual_discount', 0));
    select total_amount into v_total from public.invoices where id = v_inv;
    if v_total <> round(o.amount_total_cents / 100.0, 2) then
      raise exception 'WEB_ORDER_REVIEW: The invoice would be S$% but Stripe charged S$%, so nothing was invoiced',
        to_char(v_total, 'FM999990.00'), to_char(o.amount_total_cents / 100.0, 'FM999990.00'); end if;
    v_paid := least((o.paid_at at time zone 'Asia/Singapore')::date, (now() at time zone 'Asia/Singapore')::date);
    if v_total > 0 then
      perform public.record_invoice_payment(v_inv, jsonb_build_array(jsonb_build_object(
        'payment_method_id', ch.payment_method_id, 'amount', v_total,
        'reference', coalesce(o.stripe_payment_intent, o.stripe_session_id), 'payment_date', v_paid)),
        public.web_order_uuid('web-order-payment:' || o.stripe_session_id));
    end if;
    update public.web_orders
       set status = 'invoiced', invoice_id = v_inv, customer_id = v_customer, review_reason = null,
           candidate_customer_ids = '{}', updated_at = now()
     where id = o.id;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_reason = message_text;
    -- Passing faults: the caller tries again.
    if v_state in ('23505','40001','40P01','55P03','57014','53300') and v_reason not like 'WEB_ORDER_REVIEW:%' then
      perform set_config('request.jwt.claim.sub', coalesce(v_prev, ''), true);
      raise;
    end if;
    v_reason := regexp_replace(v_reason, '^WEB_ORDER_REVIEW:\s*', '');
    update public.web_orders
       set status = 'needs_review', review_reason = v_reason,
           candidate_customer_ids = public.web_order_phone_customers(public.normalize_customer_phone(o.buyer_phone)),
           updated_at = now()
     where id = o.id;
  end;
  perform set_config('request.jwt.claim.sub', coalesce(v_prev, ''), true);
  select * into o from public.web_orders where id = p_order_id;
  return jsonb_build_object('status', o.status,
    'invoice_no', (select invoice_no from public.invoices where id = o.invoice_id), 'review_reason', o.review_reason);
end $f$;

-- Renames the people on an invoiced order's ticket to the names the buyer gave,
-- as the channel's acting profile (the change is audited).
create or replace function public.web_order_rename_people(p_order_id uuid)
returns void language plpgsql security definer set search_path to 'public' as $f$
declare o public.web_orders%rowtype; ch public.web_order_channels%rowtype; v_prev text; v_item uuid; v_people jsonb;
begin
  select * into o from public.web_orders where id = p_order_id;
  if o.status <> 'invoiced' or jsonb_typeof(o.attendees) is distinct from 'array' then return; end if;
  select * into ch from public.web_order_channels where key = o.channel;
  select ii.id into v_item from public.invoice_items ii
   where ii.invoice_id = o.invoice_id and ii.line_kind = 'event_ticket' order by ii.id limit 1;
  if v_item is null then return; end if;
  if jsonb_array_length(o.attendees) <> (select quantity from public.invoice_items where id = v_item) then return; end if;
  -- The guests already on the line keep their records (and check-ins).
  select jsonb_agg(p.person || jsonb_strip_nulls(jsonb_build_object('guest_id', g.id)) order by p.k)
    into v_people
    from jsonb_array_elements(public.web_order_people(o, o.customer_id)) with ordinality p(person, k)
    left join public.event_guests g on g.invoice_item_id = v_item and g.line_position = p.k
                                    and (g.status = 'registered' or g.cancelled_reason in ('Invoice cancelled or refunded', 'Ticket refunded'));
  v_prev := current_setting('request.jwt.claim.sub', true);
  perform set_config('request.jwt.claim.sub', ch.acting_profile_id::text, true);
  perform public.event_sync_ticket_line(v_item, jsonb_build_object('attendees', v_people));
  -- A customer this order made takes the name parts the buyer gave, but only
  -- while it still has the name the order gave it: a name staff corrected,
  -- or a customer merged into another, is left alone.
  if o.customer_created and o.customer_id is not null and nullif(btrim(coalesce(o.buyer_first_name, '')), '') is not null
     and exists (select 1 from public.customers c where c.id = o.customer_id and c.full_name = o.buyer_name
                   and c.first_name = o.buyer_name and c.last_name is null) then
    update public.customers
       set first_name = btrim(o.buyer_first_name), last_name = nullif(btrim(coalesce(o.buyer_last_name, '')), ''),
           full_name = public.join_person_name(o.buyer_first_name, o.buyer_last_name)
     where id = o.customer_id;
    perform public.write_audit_ex('customers', o.customer_id, 'customer_named_from_website',
      jsonb_build_object('full_name', o.buyer_name),
      jsonb_build_object('full_name', public.join_person_name(o.buyer_first_name, o.buyer_last_name),
                         'stripe_session_id', o.stripe_session_id),
      'customer', 'Website order ' || o.stripe_session_id, null);
  end if;
  perform set_config('request.jwt.claim.sub', coalesce(v_prev, ''), true);
end $f$;

-- ── 3. What the website hands in (service role only) ───────────────────────

-- A paid order. Stored once per Stripe checkout; invoiced when the channel is
-- live. Returns {status, invoice_no, review_reason}.
create or replace function public.web_order_paid(p_order jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare ch public.web_order_channels%rowtype; o public.web_orders%rowtype; v_session text; v_live boolean; v_reason text;
begin
  v_session := p_order->>'stripe_session_id';
  if v_session is null or v_session !~ '^cs_(test|live)_[A-Za-z0-9]{8,200}$' then
    return jsonb_build_object('status', 'refused', 'invoice_no', null, 'review_reason', 'Not a Stripe checkout id'); end if;
  select * into ch from public.web_order_channels where key = p_order->>'channel';
  if not found then
    return jsonb_build_object('status', 'refused', 'invoice_no', null, 'review_reason', 'Unknown website channel'); end if;
  v_live := v_session like 'cs_live_%';
  if (p_order->>'livemode')::boolean is distinct from v_live then
    return jsonb_build_object('status', 'refused', 'invoice_no', null, 'review_reason', 'Live/test flag does not match the checkout'); end if;
  if coalesce(p_order->>'ticket', '') = '' or coalesce(btrim(p_order->'buyer'->>'name'), '') = ''
     or coalesce((p_order->>'quantity')::integer, 0) not between 1 and 10
     or (p_order->>'amount_total_cents')::integer is null or (p_order->>'unit_amount_cents')::integer is null
     or nullif(p_order->>'checkout_opened_at', '') is null or nullif(p_order->>'paid_at', '') is null then
    return jsonb_build_object('status', 'refused', 'invoice_no', null, 'review_reason', 'The order is incomplete'); end if;

  v_reason := case when ch.mode = 'off' then 'The website channel is off'
                   when not v_live and not ch.allow_test then 'A Stripe test payment' end;
  insert into public.web_orders
    (channel, stripe_session_id, stripe_payment_intent, livemode, status, ticket, quantity, unit_amount_cents,
     amount_total_cents, early_bird, buyer_name, buyer_email, buyer_phone, checkout_opened_at, paid_at, review_reason)
  values (ch.key, v_session, nullif(p_order->>'stripe_payment_intent', ''), v_live,
          case when v_reason is not null then 'refused' else 'recorded' end,
          p_order->>'ticket', (p_order->>'quantity')::integer, (p_order->>'unit_amount_cents')::integer,
          (p_order->>'amount_total_cents')::integer, coalesce((p_order->>'early_bird')::boolean, false),
          btrim(p_order->'buyer'->>'name'), nullif(btrim(coalesce(p_order->'buyer'->>'email', '')), ''),
          nullif(btrim(coalesce(p_order->'buyer'->>'phone', '')), ''),
          (p_order->>'checkout_opened_at')::timestamptz, (p_order->>'paid_at')::timestamptz, v_reason)
  on conflict (stripe_session_id) do nothing;
  select * into o from public.web_orders where stripe_session_id = v_session for update;
  if o.channel <> ch.key then
    return jsonb_build_object('status', 'refused', 'invoice_no', null, 'review_reason', 'The checkout belongs to another channel'); end if;

  if o.status = 'recorded' and ch.mode = 'live' then
    return public.web_order_make_invoice(o.id);
  end if;
  return jsonb_build_object('status', o.status,
    'invoice_no', (select invoice_no from public.invoices where id = o.invoice_id), 'review_reason', o.review_reason);
end $f$;

-- The names the buyer gave for everyone on the order. An invoiced order's
-- ticket is renamed; a recorded order of a live channel is invoiced with them.
-- Returns {status, invoice_no, review_reason}; 'not_found' when the payment
-- has not been handed in yet.
create or replace function public.web_order_names(p_order jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare ch public.web_order_channels%rowtype; o public.web_orders%rowtype; v_att jsonb;
begin
  select * into o from public.web_orders
   where stripe_session_id = p_order->>'stripe_session_id' and channel = p_order->>'channel' for update;
  if not found then
    return jsonb_build_object('status', 'not_found', 'invoice_no', null, 'review_reason', null); end if;
  select * into ch from public.web_order_channels where key = o.channel;
  if jsonb_typeof(p_order->'attendees') is distinct from 'array'
     or jsonb_array_length(p_order->'attendees') <> o.quantity
     or exists (select 1 from jsonb_array_elements(p_order->'attendees') x where coalesce(btrim(x->>'name'), '') = '') then
    return jsonb_build_object('status', o.status,
      'invoice_no', (select invoice_no from public.invoices where id = o.invoice_id),
      'review_reason', 'The names do not match the number of people paid for, so they were not used'); end if;
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('name', btrim(x->>'name'),
           'email', nullif(btrim(coalesce(x->>'email', '')), ''), 'whatsapp', nullif(btrim(coalesce(x->>'whatsapp', '')), ''))) order by k)
    into v_att from jsonb_array_elements(p_order->'attendees') with ordinality t(x, k);
  update public.web_orders
     set attendees = v_att, names_at = now(),
         -- The name parts the buyer typed are kept from the first delivery; a
         -- later resend cannot change them.
         buyer_first_name = coalesce(buyer_first_name, nullif(btrim(coalesce(p_order->'buyer'->>'first_name', '')), '')),
         buyer_last_name = case when buyer_first_name is null
                                then nullif(btrim(coalesce(p_order->'buyer'->>'last_name', '')), '') else buyer_last_name end,
         buyer_email = coalesce(nullif(btrim(coalesce(p_order->'buyer'->>'email', '')), ''), buyer_email),
         updated_at = now()
   where id = o.id;
  if o.status = 'invoiced' then
    perform public.web_order_rename_people(o.id);
  elsif o.status = 'recorded' and ch.mode = 'live' then
    begin
      return public.web_order_make_invoice(o.id);
    exception when others then
      -- A passing fault: the names are kept, and the invoice is made on the
      -- next delivery of the payment, or by staff.
      return jsonb_build_object('status', 'recorded', 'invoice_no', null,
        'review_reason', 'The names were kept; the invoice will be made on the next try');
    end;
  end if;
  select * into o from public.web_orders where id = o.id;
  return jsonb_build_object('status', o.status,
    'invoice_no', (select invoice_no from public.invoices where id = o.invoice_id), 'review_reason', o.review_reason);
end $f$;

-- ── 4. What the Events page calls (Owner, Admin, Manager) ──────────────────

-- An event's website channel and orders, newest first.
create or replace function public.web_orders_list(p_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $f$
declare ch public.web_order_channels%rowtype;
begin
  if not public.is_manager_or_above() then raise exception 'Only an Owner, Admin or Manager can see website orders'; end if;
  select * into ch from public.web_order_channels where event_id = p_event_id order by created_at limit 1;
  if not found then return jsonb_build_object('channel', null, 'can_switch', false, 'orders', '[]'::jsonb); end if;
  if not public.user_has_store_access(ch.store_id) then raise exception 'You do not have access to this event''s store'; end if;
  return jsonb_build_object(
    'channel', jsonb_build_object('key', ch.key, 'mode', ch.mode, 'allow_test', ch.allow_test,
      'store_name', (select name from public.stores where id = ch.store_id),
      'acting_name', (select full_name from public.profiles where id = ch.acting_profile_id),
      'payment_method_name', (select name from public.payment_methods where id = ch.payment_method_id)),
    'can_switch', public.is_owner(),
    'orders', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', o.id, 'stripe_session_id', o.stripe_session_id, 'livemode', o.livemode, 'status', o.status,
               'ticket', o.ticket,
               'ticket_label', coalesce((select eo.name from public.event_ticket_options eo
                                          where eo.id = nullif(ch.ticket_map -> o.ticket ->> 'option_id', '')::uuid), o.ticket)
                               || coalesce(' · ' || (select string_agg(to_char(d::date, 'Dy DD Mon'), ', ')
                                                      from jsonb_array_elements_text(ch.ticket_map -> o.ticket -> 'days') d
                                                     where jsonb_array_length(ch.ticket_map -> o.ticket -> 'days') <
                                                           (select count(*) from public.event_days ed where ed.event_id = ch.event_id)), ''),
               'quantity', o.quantity, 'unit_amount', round(o.unit_amount_cents / 100.0, 2),
               'amount_total', round(o.amount_total_cents / 100.0, 2), 'early_bird', o.early_bird,
               'buyer_name', o.buyer_name, 'buyer_email', o.buyer_email, 'buyer_phone', o.buyer_phone,
               'checkout_opened_at', o.checkout_opened_at, 'paid_at', o.paid_at,
               'attendees', o.attendees, 'names_at', o.names_at,
               'invoice_id', o.invoice_id, 'invoice_no', i.invoice_no, 'review_reason', o.review_reason,
               'candidates', coalesce((select jsonb_agg(jsonb_build_object('customer_id', c.id, 'full_name', c.full_name,
                                         'phone', c.phone, 'email', c.email,
                                         'last_invoice_at', (select max(i2.created_at) from public.invoices i2
                                                              where i2.customer_id = c.id and i2.deleted_at is null))
                                         order by array_position(o.candidate_customer_ids, c.id))
                                       from public.customers c where c.id = any(o.candidate_customer_ids) and c.deleted_at is null), '[]'),
               'created_at', o.created_at)
             order by o.paid_at desc, o.created_at desc)
        from public.web_orders o left join public.invoices i on i.id = o.invoice_id
       where o.channel = ch.key), '[]'));
end $f$;

-- Makes the invoice of a recorded or waiting order: for the chosen customer,
-- a new customer, or (neither) the customer matched by phone as usual.
create or replace function public.web_order_resolve(p_order_id uuid, p_customer_id uuid default null, p_new_customer boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare o public.web_orders%rowtype; ch public.web_order_channels%rowtype; v_res jsonb;
begin
  if not public.is_manager_or_above() then raise exception 'Only an Owner, Admin or Manager can create a website order''s invoice'; end if;
  select * into o from public.web_orders where id = p_order_id for update;
  if not found then raise exception 'Website order not found'; end if;
  select * into ch from public.web_order_channels where key = o.channel;
  if not public.user_has_store_access(ch.store_id) then raise exception 'You do not have access to this event''s store'; end if;
  if o.status = 'invoiced' then raise exception 'This order already has its invoice'; end if;
  if o.status = 'refused' then raise exception 'A refused order is not invoiced: %', coalesce(o.review_reason, 'refused'); end if;
  if p_customer_id is not null and p_new_customer then raise exception 'Choose a customer or a new customer, not both'; end if;
  v_res := public.web_order_make_invoice(o.id, p_customer_id, coalesce(p_new_customer, false));
  perform public.write_audit_ex('web_orders', o.id, 'web_order_resolved',
    jsonb_build_object('status', o.status, 'review_reason', o.review_reason),
    v_res || jsonb_build_object('customer_id', p_customer_id, 'new_customer', p_new_customer), 'events', null, ch.store_id);
  return v_res;
end $f$;

-- Switches a channel off, to record-only or to live (Owner only).
create or replace function public.web_order_channel_set_mode(p_key text, p_mode text)
returns void language plpgsql security definer set search_path to 'public' as $f$
declare ch public.web_order_channels%rowtype;
begin
  if not public.is_owner() then raise exception 'Only an Owner can switch a website channel'; end if;
  if p_mode not in ('off','record_only','live') then raise exception 'Choose off, record_only or live'; end if;
  select * into ch from public.web_order_channels where key = p_key for update;
  if not found then raise exception 'Website channel not found'; end if;
  update public.web_order_channels set mode = p_mode, updated_at = now() where key = p_key;
  perform public.write_audit_ex('web_order_channels', null, 'web_order_channel_mode',
    jsonb_build_object('key', p_key, 'mode', ch.mode), jsonb_build_object('key', p_key, 'mode', p_mode),
    'events', null, ch.store_id);
end $f$;

-- ── 5. Who may call what ───────────────────────────────────────────────────
revoke all on function public.web_order_uuid(text) from public, anon, authenticated;
revoke all on function public.web_order_phone_customers(text) from public, anon, authenticated;
revoke all on function public.web_order_customer(public.web_orders, public.web_order_channels, uuid, boolean) from public, anon, authenticated;
revoke all on function public.web_order_people(public.web_orders, uuid) from public, anon, authenticated;
revoke all on function public.web_order_make_invoice(uuid, uuid, boolean) from public, anon, authenticated;
revoke all on function public.web_order_rename_people(uuid) from public, anon, authenticated;
revoke all on function public.web_order_paid(jsonb) from public, anon, authenticated;
revoke all on function public.web_order_names(jsonb) from public, anon, authenticated;
grant execute on function public.web_order_uuid(text), public.web_order_phone_customers(text),
  public.web_order_customer(public.web_orders, public.web_order_channels, uuid, boolean),
  public.web_order_people(public.web_orders, uuid), public.web_order_make_invoice(uuid, uuid, boolean),
  public.web_order_rename_people(uuid), public.web_order_paid(jsonb), public.web_order_names(jsonb) to service_role;

revoke all on function public.web_orders_list(uuid) from public, anon;
revoke all on function public.web_order_resolve(uuid, uuid, boolean) from public, anon;
revoke all on function public.web_order_channel_set_mode(text, text) from public, anon;
grant execute on function public.web_orders_list(uuid), public.web_order_resolve(uuid, uuid, boolean),
  public.web_order_channel_set_mode(text, text) to authenticated, service_role;

notify pgrst, 'reload schema';
