-- 373_website_orders_hardening.sql
--
-- WEBSITE ORDERS: WHAT THE PRE-APPLY REVIEW OF 372 FOUND (1 Oct 2026)
--
--   372 is in production, but no website channel exists yet, so nothing below
--   has been reachable. This closes three gaps before the first channel is
--   added:
--
--   1. A new buyer's customer was made under a request id taken from the
--      Stripe checkout id, which the buyer sees and staff can learn. Staff who
--      knew it could make a customer under that id first, and the order would
--      take that customer. The customer is now made without a request id.
--      Nothing can replay: an order's customer is made in the same
--      transaction as its invoice, and a refusal or fault undoes both. When
--      the buyer has already named themselves on the website, the customer is
--      made with those name parts.
--   2. The times the website sends were trusted as they came. An order whose
--      times do not hang together is not invoiced by itself; it waits for
--      review. That is an order:
--        - paid more than 5 minutes later than it arrived (clocks differ a
--          little);
--        - whose checkout opened after it was paid (beyond a minute) or after
--          the order arrived;
--        - paid more than 2 hours after its checkout opened (the website's
--          checkouts last an hour);
--        - paid more than 7 days before its invoice would be made (late
--          deliveries, and orders kept while the channel was record-only).
--      These are checked first, before anything else that can hold an order
--      back. The times are taken as they are only when a Manager creates the
--      invoice of an order that waited for one of these reasons, having seen
--      it. An invoice is never dated after today; otherwise it is dated, as
--      always, on the checkout's day.
--   3. Names sent again changed the ticket again, undoing staff's work:
--        - names the order already had (the same names, and the same WhatsApp
--          for everyone after the buyer) now change nothing;
--        - new names keep what staff set on a guest: the customer they
--          linked, and a phone where the buyer gave no WhatsApp (the buyer's
--          line otherwise takes the invoice's customer and Stripe's phone);
--        - the names go on the ticket line the order made (it is remembered),
--          not on another ticket line staff added to the invoice;
--        - names that cannot go on (the line is gone, or is for a different
--          number of people) are kept on the order with the reason. The
--          Events page shows it, and a Manager puts them on from there once
--          they fit (web_order_apply_names).
--
--   Nothing else changes. Changes in shape:
--     - web_orders gains invoice_item_id, the ticket line the order made;
--     - web_order_make_invoice gains p_reviewed, which only web_order_resolve
--       sets;
--     - web_order_rename_people returns why the names could not go on (null
--       when they did);
--     - web_order_apply_names is new (Owner, Admin, Manager).
--   The payment's request id still comes from the checkout id. That is safe:
--   record_invoice_payment only replays a request id on its own invoice, and
--   the invoice is new.
--   Apply in one transaction (the Supabase migration tool does).

set lock_timeout = '5s';

-- The functions replaced here must still be exactly 372's.
do $$
declare r record; v text;
begin
  if to_regclass('public.web_orders') is null then
    raise exception '373: apply 372 (website orders) first'; end if;
  -- Once 373 is in, make_invoice has four parameters; rerunning is then fine.
  if to_regprocedure('public.web_order_make_invoice(uuid,uuid,boolean,boolean)') is not null then return; end if;
  for r in select * from (values
      ('public.web_order_customer(public.web_orders,public.web_order_channels,uuid,boolean)', 'f009c8ea06a00ad940abfb06bad9cad8'),
      ('public.web_order_make_invoice(uuid,uuid,boolean)', '38899372818cb20677e2a0bb8af9b511'),
      ('public.web_order_rename_people(uuid)', '8e8b506312fa46af01e1ee34a8a49c93'),
      ('public.web_order_names(jsonb)', '23e7427752fcabc4a81219b4d3c07caf'),
      ('public.web_order_resolve(uuid,uuid,boolean)', '3c4204bce3c8f1afbc79067e260ec899')) t(sig, want) loop
    select md5(p.prosrc) into v from pg_proc p where p.oid = to_regprocedure(r.sig);
    if v is distinct from r.want then
      raise exception '373: % is not the version 373 was written against (md5 %); stop and compare', r.sig, coalesce(v, 'missing');
    end if;
  end loop;
end $$;

-- The ticket line an order's invoice was made with, so its names go on that
-- line and no other (no foreign key: staff may edit the invoice; the names
-- step looks for the line again when it is gone).
alter table public.web_orders add column if not exists invoice_item_id uuid;

-- The helper only uses built-ins; pinning its search_path quiets the advisor.
alter function public.web_order_uuid(text) set search_path = pg_catalog;

-- ── 1. The customer an order is for ───────────────────────────────────────
-- The customer an order is for: the one chosen, a new one, or the one
-- customer with the buyer's phone (none: a new one; two or more: review).
-- Runs as the channel's acting profile.
create or replace function public.web_order_customer(p_order public.web_orders, p_channel public.web_order_channels,
  p_customer_id uuid, p_new_customer boolean)
returns uuid language plpgsql security definer set search_path to 'public' as $f$
declare v_phone text; v_ids uuid[]; v_res jsonb; v_id uuid; v_first text;
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
  -- 373: no request id. The customer is made in the same transaction as the
  -- invoice, so there is nothing to replay, and no id anyone could use first.
  -- A buyer who already named themselves on the website gets those name parts.
  v_first := nullif(btrim(coalesce(p_order.buyer_first_name, '')), '');
  v_res := public.create_customer_quick(coalesce(v_first, p_order.buyer_name),
             case when v_first is not null then nullif(btrim(coalesce(p_order.buyer_last_name, '')), '') end,
             v_phone, p_order.buyer_email);
  v_id := (v_res->>'customer_id')::uuid;
  if p_channel.source_option_id is not null then
    perform public.set_customer_source(v_id, p_channel.source_option_id, p_channel.source_details,
      'Website order ' || p_order.stripe_session_id);
  end if;
  update public.web_orders set customer_created = true where id = p_order.id;
  return v_id;
end $f$;

-- ── 2. Making the invoice ─────────────────────────────────────────────────
-- Makes the invoice of an order and records its payment, as the channel's
-- acting profile. A business refusal leaves nothing behind and puts the order
-- in review with the reason; a passing fault (a lock, a clash on the invoice
-- number) is raised, so the caller tries again. p_reviewed: a Manager is
-- creating the invoice of an order that waited because of its times, having
-- seen why (web_order_resolve), so they are taken as they are.
drop function if exists public.web_order_make_invoice(uuid, uuid, boolean);
create or replace function public.web_order_make_invoice(p_order_id uuid, p_customer_id uuid default null,
  p_new_customer boolean default false, p_reviewed boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare
  o public.web_orders%rowtype; ch public.web_order_channels%rowtype; v_prev text;
  v_customer uuid; v_map jsonb; v_items jsonb; v_inv uuid; v_total numeric; v_paid date; v_reason text; v_state text;
  v_times text; v_line uuid;
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
    -- 373: times that do not hang together wait for a person, before anything
    -- else can hold the order back. created_at is when the order first arrived.
    -- Every such reason ends with the same sentence, which web_order_resolve
    -- looks for.
    if not p_reviewed then
      v_times := case
        when o.paid_at > o.created_at + interval '5 minutes'
          then 'Stripe''s payment time is later than when the order arrived'
        when o.checkout_opened_at > least(o.paid_at + interval '1 minute', o.created_at)
          then 'The checkout opened after it was paid, or after the order arrived'
        when o.paid_at - o.checkout_opened_at > interval '2 hours'
          then 'It was paid more than 2 hours after the checkout opened'
        when now() - o.paid_at > interval '7 days'
          then 'It was paid more than 7 days ago'
      end;
      if v_times is not null then
        raise exception 'WEB_ORDER_REVIEW: %. Check the payment in Stripe before creating its invoice', v_times; end if;
    end if;
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
    -- 373: never dated after today.
    v_inv := public.create_invoice_with_details(ch.store_id, v_customer, v_items, jsonb_build_object(
      'business_date', least((o.checkout_opened_at at time zone 'Asia/Singapore')::date,
                             (now() at time zone 'Asia/Singapore')::date)::text,
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
    -- 373: the ticket line this order made (the invoice has only this one).
    select ii.id into v_line from public.invoice_items ii
     where ii.invoice_id = v_inv and ii.line_kind = 'event_ticket' limit 1;
    update public.web_orders
       set status = 'invoiced', invoice_id = v_inv, invoice_item_id = v_line, customer_id = v_customer, review_reason = null,
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

-- ── 3. Names ──────────────────────────────────────────────────────────────
-- Puts the names the buyer gave on an invoiced order's ticket line, as the
-- channel's acting profile (the change is audited). Returns why they could not
-- go on, or null.
drop function if exists public.web_order_rename_people(uuid);
create or replace function public.web_order_rename_people(p_order_id uuid)
returns text language plpgsql security definer set search_path to 'public' as $f$
declare o public.web_orders%rowtype; ch public.web_order_channels%rowtype; v_prev text; v_item uuid; v_people jsonb;
  v_customer uuid; v_qty integer; v_lines uuid[];
begin
  select * into o from public.web_orders where id = p_order_id;
  if o.status <> 'invoiced' or jsonb_typeof(o.attendees) is distinct from 'array' then return null; end if;
  select * into ch from public.web_order_channels where key = o.channel;
  -- 373: the line this order made. If staff's edits replaced it, the one
  -- line of the order's pass; none or several, and the names wait.
  select ii.id into v_item from public.invoice_items ii
   where ii.id = o.invoice_item_id and ii.invoice_id = o.invoice_id and ii.line_kind = 'event_ticket';
  if v_item is null then
    select coalesce(array_agg(ii.id), '{}') into v_lines from public.invoice_items ii
     where ii.invoice_id = o.invoice_id and ii.line_kind = 'event_ticket'
       and ii.event_ticket_option_id = nullif(ch.ticket_map -> o.ticket ->> 'option_id', '')::uuid;
    if cardinality(v_lines) = 0 then
      return 'The buyer''s names are kept here but are not on the invoice: it has no ticket line for this pass'; end if;
    if cardinality(v_lines) > 1 then
      return 'The buyer''s names are kept here but are not on the invoice: it has more than one ticket line for this pass'; end if;
    v_item := v_lines[1];
    update public.web_orders set invoice_item_id = v_item where id = o.id;
  end if;
  select ii.quantity into v_qty from public.invoice_items ii where ii.id = v_item;
  if jsonb_array_length(o.attendees) <> v_qty then
    return format('The buyer''s names are kept here but are not on the invoice: they are for %s people and its ticket line is for %s',
                  jsonb_array_length(o.attendees), v_qty); end if;
  -- 373: the buyer's line takes the invoice's customer, which staff may have changed.
  select i.customer_id into v_customer from public.invoices i where i.id = o.invoice_id;
  -- The guests already on the line keep their records (and check-ins), and
  -- what staff set on them: the customer they linked, and a phone where the
  -- buyer gave no WhatsApp.
  select jsonb_agg(p.person || jsonb_strip_nulls(jsonb_build_object(
           'guest_id', g.id,
           'customer_id', coalesce(g.customer_id, nullif(p.person->>'customer_id', '')::uuid),
           'phone', coalesce(nullif(btrim(o.attendees -> (p.k::integer - 1) ->> 'whatsapp'), ''), g.phone,
                             nullif(p.person->>'phone', '')))) order by p.k)
    into v_people
    from jsonb_array_elements(public.web_order_people(o, v_customer)) with ordinality p(person, k)
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
  return null;
end $f$;

-- The names the buyer gave for everyone on the order. An invoiced order's
-- ticket is renamed; a recorded order of a live channel is invoiced with them.
-- Returns {status, invoice_no, review_reason}; 'not_found' when the payment
-- has not been handed in yet.
create or replace function public.web_order_names(p_order jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare ch public.web_order_channels%rowtype; o public.web_orders%rowtype; v_att jsonb; v_note text; v_same boolean;
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
  -- 373: the same names as before (sent again: the same names, and the same
  -- WhatsApp for everyone after the buyer, whose own contacts the website may
  -- fill in on a resend).
  v_same := coalesce(jsonb_typeof(o.attendees) = 'array'
    and (select jsonb_agg(jsonb_build_array(btrim(x->>'name'), case when k > 1 then nullif(btrim(coalesce(x->>'whatsapp', '')), '') end) order by k)
           from jsonb_array_elements(o.attendees) with ordinality t(x, k))
      = (select jsonb_agg(jsonb_build_array(x->>'name', case when k > 1 then x->>'whatsapp' end) order by k)
           from jsonb_array_elements(v_att) with ordinality t(x, k)), false);
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
    -- 373: names the order already had change nothing, unless they are still
    -- waiting to go on the ticket.
    if not v_same or o.review_reason is not null then
      v_note := public.web_order_rename_people(o.id);
      update public.web_orders set review_reason = v_note where id = o.id;
    end if;
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
    'invoice_no', (select invoice_no from public.invoices where id = o.invoice_id),
    'review_reason', o.review_reason);
end $f$;

-- ── 4. What the Events page calls ─────────────────────────────────────────
-- Makes the invoice of a recorded or waiting order: for the chosen customer,
-- a new customer, or (neither) the customer matched by phone as usual. An
-- order that waited because of its times has shown the Manager why, so they
-- are then taken as they are; any other order is checked first.
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
  v_res := public.web_order_make_invoice(o.id, p_customer_id, coalesce(p_new_customer, false),
             o.status = 'needs_review' and coalesce(o.review_reason, '') like '%. Check the payment in Stripe before creating its invoice');
  perform public.write_audit_ex('web_orders', o.id, 'web_order_resolved',
    jsonb_build_object('status', o.status, 'review_reason', o.review_reason),
    v_res || jsonb_build_object('customer_id', p_customer_id, 'new_customer', p_new_customer), 'events', null, ch.store_id);
  return v_res;
end $f$;

-- 373: puts an invoiced order's kept names on its ticket line, once they fit
-- (after staff fixed the line). Returns {status, invoice_no, review_reason}.
create or replace function public.web_order_apply_names(p_order_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare o public.web_orders%rowtype; ch public.web_order_channels%rowtype; v_note text;
begin
  if not public.is_manager_or_above() then raise exception 'Only an Owner, Admin or Manager can put a website order''s names on its invoice'; end if;
  select * into o from public.web_orders where id = p_order_id for update;
  if not found then raise exception 'Website order not found'; end if;
  select * into ch from public.web_order_channels where key = o.channel;
  if not public.user_has_store_access(ch.store_id) then raise exception 'You do not have access to this event''s store'; end if;
  if o.status <> 'invoiced' then raise exception 'Only an invoiced order''s names can be put on its invoice'; end if;
  if jsonb_typeof(o.attendees) is distinct from 'array' then raise exception 'The buyer has not sent the names yet'; end if;
  v_note := public.web_order_rename_people(o.id);
  update public.web_orders set review_reason = v_note, updated_at = now() where id = o.id;
  perform public.write_audit_ex('web_orders', o.id, 'web_order_names_applied',
    jsonb_build_object('review_reason', o.review_reason), jsonb_build_object('review_reason', v_note), 'events', null, ch.store_id);
  return jsonb_build_object('status', o.status, 'invoice_no', (select invoice_no from public.invoices where id = o.invoice_id),
                            'review_reason', v_note);
end $f$;

-- ── 5. Who may call what ──────────────────────────────────────────────────
revoke all on function public.web_order_make_invoice(uuid, uuid, boolean, boolean) from public, anon, authenticated;
revoke all on function public.web_order_rename_people(uuid) from public, anon, authenticated;
grant execute on function public.web_order_make_invoice(uuid, uuid, boolean, boolean),
  public.web_order_rename_people(uuid) to service_role;
revoke all on function public.web_order_apply_names(uuid) from public, anon;
grant execute on function public.web_order_apply_names(uuid) to authenticated, service_role;

notify pgrst, 'reload schema';
