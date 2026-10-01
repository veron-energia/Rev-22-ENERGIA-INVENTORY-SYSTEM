-- 376 · Website orders paid through HitPay.
--
-- An event website can now take payment through HitPay (PayNow and cards) as
-- well as Stripe. A HitPay order reaches web-ticket-order like a Stripe one,
-- with provider 'hitpay', and is kept and invoiced the same way:
--
--   1. web_orders.provider says which: 'stripe' (every order before this one,
--      and any order sent without a provider) or 'hitpay'. A HitPay order keeps
--      HitPay's payment request id (a lower-case uuid) in stripe_session_id and
--      HitPay's payment id in stripe_payment_intent; the columns keep their
--      names, so nothing else moves. The two kinds of id never collide.
--   2. HitPay's ids do not say sandbox or production, so a HitPay order's
--      livemode is what the website says (the request is signed). A sandbox
--      order is refused like a Stripe test payment unless the channel accepts
--      test orders.
--   3. A HitPay order's invoice is paid with the channel's HitPay method,
--      "HitPay (online)" (added here) unless the channel names another, with
--      HitPay's payment id as the reference. Its notes and every reason name
--      HitPay; a Stripe order's are word for word what they were.
--   4. web_order_resolve recognises the time reasons of either provider, and
--      web_orders_list says each order's provider and the channel's HitPay
--      method.

do $$ begin
  if to_regprocedure('public.web_order_apply_names(uuid)') is null then
    raise exception '376: apply 372 and 373 first'; end if;
end $$;

-- The four functions this replaces must be the ones it was tested against:
-- production's (373's make_invoice and resolve, 372's paid and list), or this
-- file's own, so it can be run again. md5 of prosrc.
do $$ declare v record; begin
  for v in select * from (values
      ('public.web_order_paid(jsonb)', array['ca0b4273ee7dc9a4841fab13daaa4cb9', '801771088f75d71f64c3004c373df67f']),
      ('public.web_order_make_invoice(uuid,uuid,boolean,boolean)', array['c7cbe3eb576a2b0ba51b03152ee6bc90', '3c0ec1cf1851c927a4a2eb844d87b047']),
      ('public.web_order_resolve(uuid,uuid,boolean)', array['d2aa99ad58fb275245169c517fbc5d1b', 'ab0f781c6757ade1acb299ddecbf1371']),
      ('public.web_orders_list(uuid)', array['2f12bbd6c750636412cd6c8577c2d8a7', '08d30c12812b06fd5b46c03787f310d5'])) t(fn, ok)
  loop
    if coalesce((select md5(prosrc) from pg_proc where oid = to_regprocedure(v.fn)), 'missing') <> all (v.ok) then
      raise exception '376: % is not the version this was tested against', v.fn; end if;
  end loop;
end $$;

-- ── 1. The HitPay payment method, and which one a website uses ─────────────
insert into public.payment_methods (name, is_active)
select 'HitPay (online)', true
 where not exists (select 1 from public.payment_methods where lower(name) = lower('HitPay (online)'));

alter table public.web_order_channels
  add column if not exists hitpay_payment_method_id uuid references public.payment_methods(id);
update public.web_order_channels
   set hitpay_payment_method_id = (select id from public.payment_methods
                                    where lower(name) = lower('HitPay (online)') and deleted_at is null
                                    order by created_at limit 1),
       updated_at = now()
 where hitpay_payment_method_id is null;

-- ── 2. Which provider took the payment ─────────────────────────────────────
alter table public.web_orders add column if not exists provider text not null default 'stripe';
alter table public.web_orders drop constraint if exists web_orders_provider;
alter table public.web_orders add constraint web_orders_provider check (provider in ('stripe', 'hitpay'));

-- 'Stripe' or 'HitPay', for notes and reasons.
create or replace function public.web_order_provider_name(p_provider text)
returns text language sql immutable set search_path to 'public' as $f$
  select case p_provider when 'hitpay' then 'HitPay' else 'Stripe' end
$f$;

-- The method a channel's invoices are paid with: the channel's own for Stripe;
-- for HitPay the channel's HitPay method, or "HitPay (online)" when it names none.
create or replace function public.web_order_payment_method(p_channel public.web_order_channels, p_provider text)
returns uuid language sql stable set search_path to 'public' as $f$
  select case when p_provider = 'hitpay'
           then coalesce(p_channel.hitpay_payment_method_id,
                         (select id from public.payment_methods
                           where lower(name) = lower('HitPay (online)') and is_active and deleted_at is null
                           order by created_at limit 1))
           else p_channel.payment_method_id end
$f$;

-- ── 3. What the website hands in ───────────────────────────────────────────
-- 372's web_order_paid, with the provider. Stripe orders are checked exactly
-- as before.
create or replace function public.web_order_paid(p_order jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare ch public.web_order_channels%rowtype; o public.web_orders%rowtype; v_session text; v_live boolean; v_reason text;
  v_provider text;
begin
  -- 376: Stripe unless the website says HitPay.
  v_provider := coalesce(nullif(p_order->>'provider', ''), 'stripe');
  if v_provider not in ('stripe', 'hitpay') then
    return jsonb_build_object('status', 'refused', 'invoice_no', null, 'review_reason', 'Unknown payment provider'); end if;
  v_session := p_order->>'stripe_session_id';
  if v_provider = 'stripe' and (v_session is null or v_session !~ '^cs_(test|live)_[A-Za-z0-9]{8,200}$') then
    return jsonb_build_object('status', 'refused', 'invoice_no', null, 'review_reason', 'Not a Stripe checkout id'); end if;
  if v_provider = 'hitpay'
     and (v_session is null or v_session !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then
    return jsonb_build_object('status', 'refused', 'invoice_no', null, 'review_reason', 'Not a HitPay payment request id'); end if;
  select * into ch from public.web_order_channels where key = p_order->>'channel';
  if not found then
    return jsonb_build_object('status', 'refused', 'invoice_no', null, 'review_reason', 'Unknown website channel'); end if;
  if v_provider = 'stripe' then
    v_live := v_session like 'cs_live_%';
    if (p_order->>'livemode')::boolean is distinct from v_live then
      return jsonb_build_object('status', 'refused', 'invoice_no', null, 'review_reason', 'Live/test flag does not match the checkout'); end if;
  else
    -- 376: HitPay's ids do not say sandbox or production; the signed request does.
    v_live := (p_order->>'livemode')::boolean;
  end if;
  if v_live is null or coalesce(p_order->>'ticket', '') = '' or coalesce(btrim(p_order->'buyer'->>'name'), '') = ''
     or coalesce((p_order->>'quantity')::integer, 0) not between 1 and 10
     or (p_order->>'amount_total_cents')::integer is null or (p_order->>'unit_amount_cents')::integer is null
     or nullif(p_order->>'checkout_opened_at', '') is null or nullif(p_order->>'paid_at', '') is null then
    return jsonb_build_object('status', 'refused', 'invoice_no', null, 'review_reason', 'The order is incomplete'); end if;

  v_reason := case when ch.mode = 'off' then 'The website channel is off'
                   when not v_live and not ch.allow_test
                     then 'A ' || public.web_order_provider_name(v_provider) || ' test payment' end;
  insert into public.web_orders
    (channel, provider, stripe_session_id, stripe_payment_intent, livemode, status, ticket, quantity, unit_amount_cents,
     amount_total_cents, early_bird, buyer_name, buyer_email, buyer_phone, checkout_opened_at, paid_at, review_reason)
  values (ch.key, v_provider, v_session, nullif(p_order->>'stripe_payment_intent', ''), v_live,
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
  if o.provider <> v_provider then
    return jsonb_build_object('status', 'refused', 'invoice_no', null, 'review_reason', 'The checkout belongs to another payment provider'); end if;

  if o.status = 'recorded' and ch.mode = 'live' then
    return public.web_order_make_invoice(o.id);
  end if;
  return jsonb_build_object('status', o.status,
    'invoice_no', (select invoice_no from public.invoices where id = o.invoice_id), 'review_reason', o.review_reason);
end $f$;

-- ── 4. The invoice ─────────────────────────────────────────────────────────
-- 373's web_order_make_invoice, with the provider: its name in the notes and
-- reasons, and its payment method.
create or replace function public.web_order_make_invoice(p_order_id uuid, p_customer_id uuid default null,
  p_new_customer boolean default false, p_reviewed boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare
  o public.web_orders%rowtype; ch public.web_order_channels%rowtype; v_prev text;
  v_customer uuid; v_map jsonb; v_items jsonb; v_inv uuid; v_total numeric; v_paid date; v_reason text; v_state text;
  v_times text; v_line uuid; v_name text; v_method uuid;
begin
  select * into o from public.web_orders where id = p_order_id for update;
  if not found then raise exception 'Website order not found'; end if;
  if o.status = 'invoiced' then
    return jsonb_build_object('status', 'invoiced', 'invoice_no', (select invoice_no from public.invoices where id = o.invoice_id),
                              'review_reason', null);
  end if;
  select * into ch from public.web_order_channels where key = o.channel;
  v_name := public.web_order_provider_name(o.provider);
  -- A test payment is never invoiced unless the channel allows it now,
  -- whenever it was recorded.
  if not o.livemode and not ch.allow_test then
    update public.web_orders set status = 'refused', review_reason = 'A ' || v_name || ' test payment', updated_at = now()
     where id = o.id;
    return jsonb_build_object('status', 'refused', 'invoice_no', null, 'review_reason', 'A ' || v_name || ' test payment');
  end if;
  v_prev := current_setting('request.jwt.claim.sub', true);
  perform set_config('request.jwt.claim.sub', ch.acting_profile_id::text, true);
  begin
    -- 373: times that do not hang together wait for a person, before anything
    -- else can hold the order back. created_at is when the order first arrived.
    -- Every such reason ends with the same sentence (naming the provider),
    -- which web_order_resolve looks for.
    if not p_reviewed then
      v_times := case
        when o.paid_at > o.created_at + interval '5 minutes'
          then v_name || '''s payment time is later than when the order arrived'
        when o.checkout_opened_at > least(o.paid_at + interval '1 minute', o.created_at)
          then 'The checkout opened after it was paid, or after the order arrived'
        when o.paid_at - o.checkout_opened_at > interval '2 hours'
          then 'It was paid more than 2 hours after the checkout opened'
        when now() - o.paid_at > interval '7 days'
          then 'It was paid more than 7 days ago'
      end;
      if v_times is not null then
        raise exception 'WEB_ORDER_REVIEW: %. Check the payment in % before creating its invoice', v_times, v_name; end if;
    end if;
    if not exists (select 1 from public.profiles p where p.id = ch.acting_profile_id and p.is_active and p.deleted_at is null
                     and p.role in ('owner','admin','manager')) then
      raise exception 'WEB_ORDER_REVIEW: The profile that raises website invoices is not an active Owner, Admin or Manager'; end if;
    v_map := ch.ticket_map -> o.ticket;
    if v_map is null or nullif(v_map->>'option_id', '') is null then
      raise exception 'WEB_ORDER_REVIEW: The website pass "%" is not linked to a ticket of the event', o.ticket; end if;
    -- 376: the provider's payment method, before anything is made.
    v_method := public.web_order_payment_method(ch, o.provider);
    if v_method is null then
      raise exception 'WEB_ORDER_REVIEW: The website has no payment method for % orders', v_name; end if;
    v_customer := public.web_order_customer(o, ch, p_customer_id, p_new_customer);
    v_items := jsonb_build_array(jsonb_build_object(
      'kind', 'event_ticket', 'event_ticket_option_id', v_map->>'option_id', 'quantity', o.quantity,
      'event_days', coalesce(v_map->'days', '[]'::jsonb),
      'attendees', public.web_order_people(o, v_customer)));
    -- 373: never dated after today.
    v_inv := public.create_invoice_with_details(ch.store_id, v_customer, v_items, jsonb_build_object(
      'business_date', least((o.checkout_opened_at at time zone 'Asia/Singapore')::date,
                             (now() at time zone 'Asia/Singapore')::date)::text,
      'notes', 'Website order · ' || v_name || ' ' || o.stripe_session_id || case when o.early_bird then ' · early bird' else '' end,
      'manual_discount', 0));
    select total_amount into v_total from public.invoices where id = v_inv;
    if v_total <> round(o.amount_total_cents / 100.0, 2) then
      raise exception 'WEB_ORDER_REVIEW: The invoice would be S$% but % charged S$%, so nothing was invoiced',
        to_char(v_total, 'FM999990.00'), v_name, to_char(o.amount_total_cents / 100.0, 'FM999990.00'); end if;
    v_paid := least((o.paid_at at time zone 'Asia/Singapore')::date, (now() at time zone 'Asia/Singapore')::date);
    if v_total > 0 then
      perform public.record_invoice_payment(v_inv, jsonb_build_array(jsonb_build_object(
        'payment_method_id', v_method, 'amount', v_total,
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

-- ── 5. Staff ───────────────────────────────────────────────────────────────
-- 373's web_order_resolve: a time reason of either provider was seen by the
-- Manager who resolves it.
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
             o.status = 'needs_review'
             and coalesce(o.review_reason, '') like '%. Check the payment in ' || public.web_order_provider_name(o.provider)
                                                   || ' before creating its invoice');
  perform public.write_audit_ex('web_orders', o.id, 'web_order_resolved',
    jsonb_build_object('status', o.status, 'review_reason', o.review_reason),
    v_res || jsonb_build_object('customer_id', p_customer_id, 'new_customer', p_new_customer), 'events', null, ch.store_id);
  return v_res;
end $f$;

-- 372's web_orders_list, with each order's provider and the channel's HitPay method.
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
      'payment_method_name', (select name from public.payment_methods where id = ch.payment_method_id),
      'hitpay_payment_method_name', (select name from public.payment_methods
                                      where id = public.web_order_payment_method(ch, 'hitpay'))),
    'can_switch', public.is_owner(),
    'orders', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', o.id, 'provider', o.provider, 'stripe_session_id', o.stripe_session_id, 'livemode', o.livemode,
               'status', o.status, 'ticket', o.ticket,
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

-- ── 6. Grants ──────────────────────────────────────────────────────────────
-- The replaced functions keep theirs; the helpers are for these functions only.
revoke all on function public.web_order_provider_name(text) from public, anon, authenticated;
revoke all on function public.web_order_payment_method(public.web_order_channels, text) from public, anon, authenticated;
grant execute on function public.web_order_provider_name(text),
                         public.web_order_payment_method(public.web_order_channels, text) to service_role;
