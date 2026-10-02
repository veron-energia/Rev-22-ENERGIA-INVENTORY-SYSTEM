-- 380_seminar_staff_link_orders.sql
--
-- STAFF-LINK REGISTRATIONS COME INTO THE INVENTORY (the owner's answers, 2 Oct
-- 2026; they replace 372's "door sales are invoiced by hand")
--
--   An event website's staff link (/register?code=..., one shared code, which
--   staff also send to customers who paid by PayNow or bank transfer) makes
--   registrations with ids OFF-YYYYMMDD-XXXXXX. Until now they never reached
--   the inventory, and staff typed each one into an invoice by hand. Now the
--   website sends each one here through the signed edge function
--   (web-ticket-order, message 'door'), and:
--
--   1. It is kept as a website order (provider 'door') and shows in the Event
--      page's Website orders tab. It is NEVER invoiced by itself, even on a
--      live channel: a Manager checks the money arrived and clicks Create
--      invoice (web_order_resolve), which makes the invoice and the guests.
--   2. The invoice is paid with the method chosen on the form: cash, PayNow or
--      bank transfer, each mapped to the channel's payment method of that name
--      (web_order_channels.door_methods, filled below from the one active
--      "Cash", "PayNow" and "Bank Transfer"). The form's reference is the
--      payment's reference (else the OFF id).
--   3. The form says the amount and the date paid. The early bird follows the
--      date paid, by the event's own rule (event_ticket_price). On arrival the
--      order waits for a Manager (needs_review, with every reason) when:
--        - the amount is not the price of that pass for that many people on
--          the date paid;
--        - the date paid is after today (Singapore), or more than 60 days
--          before the registration;
--        - the registration time is more than 5 minutes in the future;
--        - another staff-link order of the channel (not dismissed) has the same
--          phone, pass and number of people within 24 hours ("possibly the same
--          as OFF-...");
--        - the staff member chosen as Registered by is not active (then no one
--          is credited).
--      Otherwise it is recorded. Create invoice still never makes an invoice
--      whose total differs from the amount paid (372's rule).
--   4. The invoice is at the channel's store, raised by the channel's acting
--      profile, dated on the date paid (never after today), with the buyer
--      matched by phone exactly as for online orders.
--   5. Registered by (optional) becomes the invoice's service staff and its
--      guests' registered_by.
--   6. A Manager can link an order to an invoice made by hand instead
--      (web_order_link_preview, web_order_link_invoice), and dismiss a
--      staff-link registration that is a test, with a reason, and restore it
--      (web_order_dismiss). The Website orders list names any invoice made by
--      hand for the event with the buyer's phone (a hint, not a reason to
--      wait), and a staff-link registration refused while the channel was off
--      (which staff invoice by hand) can be linked too.
--   7. Every registration reaches the three Excels: web_orders_list gains the
--      staff-link fields; event_guest_list gains each guest's email, website
--      order and the invoice's payment methods; and the website asks for its
--      orders' invoice numbers and for the tickets sold at the counter
--      (web_order_sync, at most once a minute), and for the staff it may
--      offer as Registered by (web_order_staff). The sync numbers each ticket
--      person once (web_order_sync_positions), so the sheet's "2 of 3" stays
--      that person when someone is taken off or added, and keeps listing a
--      deleted counter sale it has listed before, its people cancelled.
--
--   Online (Stripe, HitPay) orders behave exactly as before.
--
-- Changes in shape:
--   - web_orders: provider may be 'door', status may be 'dismissed'; new
--     columns door_method, payment_reference, staff_profile_id, paid_on. A
--     staff-link order keeps its OFF id in stripe_session_id (the columns keep
--     their names, as in 376), no payment intent, livemode true, the
--     registration time as checkout_opened_at and paid_at, and its names on
--     arrival (as 'names' keeps them).
--   - web_order_channels: door_methods {"cash","paynow","bank": payment
--     method id} and last_sync_at.
--   - New table web_order_sync_positions (event, guest, invoice, position),
--     written only by these functions.
--   - New (service role only): web_order_door, web_order_sync,
--     web_order_staff, and their helpers.
--   - New (Owner, Admin, Manager, of the event's store):
--     web_order_link_preview, web_order_link_invoice, web_order_dismiss.
--   - Replaced: web_order_make_invoice (a staff-link branch, staff-link
--     orders only for a Manager, and the people's numbers), web_order_resolve
--     (refuses a dismissed order), web_orders_list (staff-link fields and the
--     hand invoices), web_order_names (leaves staff-link orders alone),
--     event_guest_list (three fields).
--
-- DEPLOY ORDER: apply this, then deploy the edge function (its new messages
-- call the new functions), then the website. The Events page reads every new
-- field as optional.
--
-- SAFETY: the five functions replaced here must be production's (md5 of
-- prosrc, 2 Oct 2026) or this file's own, so it can be run again; the ones it
-- relies on must be production's. Every check runs before anything changes.
-- Apply in one transaction (the Supabase migration tool does). Nothing
-- existing is dropped; existing rows only gain the new columns' defaults, and
-- each channel's door_methods is filled once (while it is still '{}'). The
-- price functions are guarded too (event_ticket_price, event_ticket_price_date,
-- production's as 377 checked them), so the arrival check and the invoice
-- cannot price a pass differently.
-- 381 (separate) adds the pings that make the website sync every 10 minutes.
--
-- AFTER (md5(prosrc), checked on a local copy whose guarded functions match
-- production, 2 Oct 2026):
--   web_order_make_invoice(uuid,uuid,boolean,boolean)  ab59ad85375ac6ce0de559f8f8d42027
--   web_order_resolve(uuid,uuid,boolean)               51ad899277e85dd767d76db0ce18d073
--   web_orders_list(uuid)                              ad5bbe1684b38e4b4f0e000ae8776f50
--   web_order_names(jsonb)                             6374a6f8bf0044e1b529d835aff56b92
--   event_guest_list(uuid)                             4983ec5037251f5db9db0599167aa44d

set lock_timeout = '5s';

-- ── 0. The versions this was tested against ────────────────────────────────
do $$ declare v record; begin
  if to_regprocedure('public.web_order_payment_method(public.web_order_channels,text)') is null then
    raise exception '380: apply 376 (HitPay orders) first'; end if;
  -- Replaced here: production's, or this file's own (a second run).
  for v in select * from (values
      ('public.web_order_make_invoice(uuid,uuid,boolean,boolean)', array['3c0ec1cf1851c927a4a2eb844d87b047', 'ab59ad85375ac6ce0de559f8f8d42027']),
      ('public.web_order_resolve(uuid,uuid,boolean)',              array['ab0f781c6757ade1acb299ddecbf1371', '51ad899277e85dd767d76db0ce18d073']),
      ('public.web_orders_list(uuid)',                             array['08d30c12812b06fd5b46c03787f310d5', 'ad5bbe1684b38e4b4f0e000ae8776f50']),
      ('public.web_order_names(jsonb)',                            array['067232247f203d5d03477a479158ed7b', '6374a6f8bf0044e1b529d835aff56b92']),
      ('public.event_guest_list(uuid)',                            array['ee35e1efdb1c7e06574dd05ef1d697ce', '4983ec5037251f5db9db0599167aa44d']),
      -- Relied on, not changed: how an order is handed in (web_order_paid
      -- refuses a 'door' provider and an OFF id), its customer, people,
      -- method and names, and the invoice and payment it makes.
      ('public.web_order_paid(jsonb)',                             array['801771088f75d71f64c3004c373df67f']),
      ('public.web_order_customer(public.web_orders,public.web_order_channels,uuid,boolean)', array['9bcbd37a2e589019637898a5d560a628']),
      ('public.web_order_people(public.web_orders,uuid)',          array['d6fe42318358d49788a07bc3d09b3228']),
      ('public.web_order_payment_method(public.web_order_channels,text)', array['f15fb7624e54f3cc48ad6f652bb29cb0']),
      ('public.web_order_provider_name(text)',                     array['5f570e81d2d293489bfb5587789eb47a']),
      ('public.web_order_rename_people(uuid)',                     array['4d4849cf07a7c832174bdffd08674510']),
      ('public.web_order_apply_names(uuid)',                       array['b9e85661a719561d7fd62fec672c14ab']),
      ('public.create_invoice_with_details(uuid,uuid,jsonb,jsonb)', array['39a0a106b4429eaa8a871ce4ac69c37b']),
      ('public.record_invoice_payment(uuid,jsonb,uuid)',           array['89f75dfbab873e71a571e14791d8a9fe']),
      -- The price a registration is checked against on arrival
      -- (event_ticket_price on the date paid) and the one its invoice is made
      -- at (create_invoice, through event_ticket_price_date): production's, as
      -- 377 checked them, so the two cannot drift apart.
      ('public.event_ticket_price(uuid,date)',                     array['3978a78664e462439ffe5b06c6237299']),
      ('public.event_ticket_price_date(date)',                     array['a208908691424af1350a7eade61b549b'])) t(fn, ok)
  loop
    if coalesce((select md5(prosrc) from pg_proc where oid = to_regprocedure(v.fn)), 'missing') <> all (v.ok) then
      raise exception '380: % is not the version this was tested against', v.fn; end if;
  end loop;
end $$;

-- ── 1. What a staff-link order keeps ───────────────────────────────────────
alter table public.web_orders
  add column if not exists door_method text,
  add column if not exists payment_reference text,
  add column if not exists staff_profile_id uuid references public.profiles(id) on delete set null,
  add column if not exists paid_on date;
alter table public.web_orders drop constraint if exists web_orders_provider;
alter table public.web_orders add constraint web_orders_provider check (provider in ('stripe', 'hitpay', 'door'));
alter table public.web_orders drop constraint if exists web_orders_status;
alter table public.web_orders add constraint web_orders_status
  check (status in ('recorded', 'invoiced', 'needs_review', 'refused', 'dismissed'));
alter table public.web_orders drop constraint if exists web_orders_door_method;
alter table public.web_orders add constraint web_orders_door_method
  check (door_method is null or door_method in ('cash', 'paynow', 'bank'));
alter table public.web_orders drop constraint if exists web_orders_door_whole;
alter table public.web_orders add constraint web_orders_door_whole
  check (provider <> 'door' or (door_method is not null and paid_on is not null));

-- Which payment method each form choice is paid with, and when the website
-- last synced.
alter table public.web_order_channels
  add column if not exists door_methods jsonb not null default '{}'::jsonb,
  add column if not exists last_sync_at timestamptz;
alter table public.web_order_channels drop constraint if exists web_order_channels_door_methods;
alter table public.web_order_channels add constraint web_order_channels_door_methods
  check (jsonb_typeof(door_methods) = 'object');
-- Each channel once: the one active "Cash", "PayNow" and "Bank Transfer". A
-- name with none, or more than one, is left out (Create invoice then says so).
update public.web_order_channels
   set door_methods = (select coalesce(jsonb_object_agg(k.choice, m.ids[1]), '{}'::jsonb)
                         from (values ('cash', 'Cash'), ('paynow', 'PayNow'), ('bank', 'Bank Transfer')) k(choice, name)
                         cross join lateral (select array_agg(pm.id) as ids from public.payment_methods pm
                                              where lower(btrim(pm.name)) = lower(k.name)
                                                and pm.is_active and pm.deleted_at is null) m
                        where cardinality(m.ids) = 1),
       updated_at = now()
 where door_methods = '{}'::jsonb;

-- The number the website's sheet knows each ticket person by ("2 of 3"):
-- given once, when an order's invoice is made or linked, or the first time a
-- sync lists the invoice, and never changed. A person taken off a line keeps
-- theirs (and is listed as cancelled); one added gets the next. A line's
-- positions are renumbered when someone is taken off it, so they cannot be
-- the sheet's numbers.
create table if not exists public.web_order_sync_positions (
  event_id   uuid not null references public.events(id) on delete cascade,
  guest_id   uuid not null references public.event_guests(id) on delete cascade,
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  position   integer not null check (position > 0),
  created_at timestamptz not null default now(),
  primary key (event_id, guest_id),
  constraint web_order_sync_positions_once unique (event_id, invoice_id, position)
);
alter table public.web_order_sync_positions enable row level security;
revoke all on table public.web_order_sync_positions from anon, authenticated;
grant all on table public.web_order_sync_positions to service_role;

-- ── 2. The rules (internal) ────────────────────────────────────────────────

-- The payment method name of a form choice.
create or replace function public.web_order_door_method_name(p_method text)
returns text language sql immutable set search_path to 'public' as $f$
  select case p_method when 'cash' then 'Cash' when 'paynow' then 'PayNow' when 'bank' then 'Bank Transfer' end
$f$;

-- Whether a profile can be credited with a sale: active staff whom an invoice
-- takes as service staff (Owner, Manager or Staff, as create_invoice checks).
create or replace function public.web_order_seller(p_profile_id uuid)
returns boolean language sql stable security definer set search_path to 'public' as $f$
  select p_profile_id is not null
     and exists (select 1 from public.profiles p where p.id = p_profile_id and p.is_active and p.deleted_at is null
                   and p.role in ('owner', 'manager', 'staff'))
$f$;

-- Why a staff-link order must wait for a Manager, or null. On arrival, and
-- again when a dismissed one is restored. The price is the event's own, on
-- the date paid.
create or replace function public.web_order_door_review(p_order public.web_orders, p_channel public.web_order_channels)
returns text language plpgsql stable security definer set search_path to 'public' as $f$
declare v_reasons text[] := '{}'; v_option public.event_ticket_options%rowtype; v_price numeric; v_same text;
  v_phone text := public.normalize_customer_phone(p_order.buyer_phone);
begin
  select * into v_option from public.event_ticket_options
   where id = nullif(p_channel.ticket_map -> p_order.ticket ->> 'option_id', '')::uuid;
  if not found then
    v_reasons := v_reasons || format('The website pass "%s" is not linked to a ticket of the event', p_order.ticket);
  else
    v_price := round(public.event_ticket_price(v_option.id, p_order.paid_on) * p_order.quantity, 2);
    if v_price <> round(p_order.amount_total_cents / 100.0, 2) then
      v_reasons := v_reasons || format('S$%s was paid, but %s × "%s" paid on %s costs S$%s',
        to_char(p_order.amount_total_cents / 100.0, 'FM999990.00'), p_order.quantity, v_option.name,
        to_char(p_order.paid_on, 'DD Mon YYYY'), to_char(v_price, 'FM999990.00'));
    end if;
  end if;
  if p_order.paid_on > (now() at time zone 'Asia/Singapore')::date then
    v_reasons := v_reasons || format('The date paid (%s) is after today', to_char(p_order.paid_on, 'DD Mon YYYY'));
  elsif p_order.paid_on < (p_order.checkout_opened_at at time zone 'Asia/Singapore')::date - 60 then
    v_reasons := v_reasons || format('The date paid (%s) is more than 60 days before the registration',
                                     to_char(p_order.paid_on, 'DD Mon YYYY'));
  end if;
  if p_order.checkout_opened_at > now() + interval '5 minutes' then
    v_reasons := v_reasons || 'The registration time is in the future'::text;
  end if;
  if v_phone is not null then
    select string_agg(o2.stripe_session_id, ', ' order by o2.checkout_opened_at) into v_same
      from public.web_orders o2
     where o2.channel = p_order.channel and o2.provider = 'door' and o2.status <> 'dismissed'
       and o2.stripe_session_id <> p_order.stripe_session_id
       and o2.ticket = p_order.ticket and o2.quantity = p_order.quantity
       and o2.checkout_opened_at between p_order.checkout_opened_at - interval '24 hours'
                                     and p_order.checkout_opened_at + interval '24 hours'
       and public.normalize_customer_phone(o2.buyer_phone) = v_phone;
    if v_same is not null then
      v_reasons := v_reasons || format('Possibly the same as %s (the same phone, pass and number of people within 24 hours)', v_same);
    end if;
  end if;
  if p_order.staff_profile_id is not null and not public.web_order_seller(p_order.staff_profile_id) then
    v_reasons := v_reasons || 'The staff member chosen as Registered by is not active staff, so no one is credited'::text;
  end if;
  return nullif(array_to_string(v_reasons, '. '), '');
end $f$;

-- The payment methods an invoice is paid with now: its receipts and the
-- replacements of corrected ones, not what a correction reversed.
create or replace function public.web_order_invoice_methods(p_invoice_id uuid)
returns text language sql stable security definer set search_path to 'public' as $f$
  select string_agg(distinct m.name, ', ' order by m.name)
    from public.invoice_payments p join public.payment_methods m on m.id = p.payment_method_id
   where p.invoice_id = p_invoice_id and p.entry_kind in ('receipt', 'correction_replacement')
     and not exists (select 1 from public.invoice_payments x
                      where x.corrects_payment_id = p.id and x.entry_kind = 'correction_reversal')
$f$;

-- The email a website order gave for the person at a place on its ticket
-- line (the buyer's for the first), only while that person still has the
-- name the order gave there: a line made by hand and linked to the order, or
-- renamed since, gets none from it.
create or replace function public.web_order_person_email(p_order public.web_orders, p_position integer, p_name text)
returns text language sql stable set search_path to 'public' as $f$
  select case
    when lower(btrim(p_order.attendees -> (p_position - 1) ->> 'name')) = lower(btrim(p_name))
      then coalesce(nullif(btrim(p_order.attendees -> (p_position - 1) ->> 'email'), ''),
                    case when p_position = 1 then p_order.buyer_email end)
    when p_position = 1 and lower(btrim(p_order.buyer_name)) = lower(btrim(p_name)) then p_order.buyer_email
  end
$f$;

-- Gives the event's ticket people on an invoice (every invoice that is not
-- deleted, when p_invoice_id is null) the sheet's numbers they do not have
-- yet, after the invoice's last: those created together in the order they
-- stand on their lines, the website order's own line first. People already
-- taken off a line are never numbered.
create or replace function public.web_order_number_people(p_event_id uuid, p_invoice_id uuid)
returns void language sql security definer set search_path to 'public' as $f$
  insert into public.web_order_sync_positions (event_id, guest_id, invoice_id, position)
  select p_event_id, g.id, g.invoice_id,
         coalesce((select max(n.position) from public.web_order_sync_positions n
                    where n.event_id = p_event_id and n.invoice_id = g.invoice_id), 0)
         + row_number() over (partition by g.invoice_id
             order by g.created_at,
                      g.invoice_item_id is distinct from (select w.invoice_item_id from public.web_orders w
                                                           where w.invoice_id = g.invoice_id order by w.created_at limit 1),
                      g.invoice_item_id, g.line_position, g.id)
    from public.event_guests g
    join public.invoices i on i.id = g.invoice_id and i.deleted_at is null
   where g.event_id = p_event_id and g.source = 'ticket' and g.line_position is not null
     and (p_invoice_id is null or g.invoice_id = p_invoice_id)
     and not exists (select 1 from public.web_order_sync_positions n where n.event_id = p_event_id and n.guest_id = g.id)
  on conflict do nothing
$f$;

-- The people on an invoice's tickets to an event, for the website's sheet,
-- by the number each was given (web_order_number_people). Those taken off a
-- line since, or whose invoice or ticket was cancelled or refunded, say
-- 'cancelled'. The email is the customer's, else the one the order gave for
-- that person.
create or replace function public.web_order_invoice_people(p_invoice_id uuid, p_event_id uuid,
  p_order public.web_orders, p_with_registered_by boolean)
returns jsonb language sql stable security definer set search_path to 'public' as $f$
  select coalesce(jsonb_agg(jsonb_build_object('position', q.pos, 'name', q.name, 'phone', q.phone, 'email', q.email,
                                               'days', q.days, 'status', q.status)
                            || case when p_with_registered_by then jsonb_build_object('registered_by', q.registered_by)
                                    else '{}'::jsonb end
                            order by q.pos), '[]'::jsonb)
    from (select n.position as pos, g.name, g.phone, g.status, rb.full_name as registered_by,
                 coalesce(nullif(btrim(c.email), ''),
                          case when g.invoice_item_id = p_order.invoice_item_id
                               then public.web_order_person_email(p_order, g.line_position, g.name) end) as email,
                 coalesce((select jsonb_agg(to_char(gd.day, 'YYYY-MM-DD') order by gd.day)
                             from public.event_guest_days gd where gd.guest_id = g.id), '[]'::jsonb) as days
            from public.web_order_sync_positions n
            join public.event_guests g on g.id = n.guest_id
            left join public.customers c on c.id = g.customer_id
            left join public.profiles rb on rb.id = g.registered_by
           where n.event_id = p_event_id and n.invoice_id = p_invoice_id
             and g.invoice_id = p_invoice_id and g.event_id = p_event_id and g.source = 'ticket') q
$f$;

-- Invoices made by hand that may already be an open order's: tickets to the
-- channel's event on an invoice that is not deleted, cancelled or refunded
-- and is no website order's, for a customer or a guest with the buyer's
-- phone. A hint for the Manager (Link existing invoice), not a reason to
-- wait. The number only of an invoice at a store the person works in.
create or replace function public.web_order_hand_invoices(p_order public.web_orders, p_channel public.web_order_channels)
returns jsonb language sql stable security definer set search_path to 'public' as $f$
  with e as (select distinct g.invoice_id from public.event_guests g
              where g.event_id = p_channel.event_id and g.source = 'ticket' and g.invoice_id is not null)
  select coalesce(jsonb_agg(jsonb_build_object(
           'invoice_no', case when public.user_has_store_access(i.store_id) then i.invoice_no end,
           'store', (select s.name from public.stores s where s.id = i.store_id))
           order by i.business_date, i.invoice_no), '[]'::jsonb)
    from e join public.invoices i on i.id = e.invoice_id
    left join public.customers c on c.id = i.customer_id
   where public.normalize_customer_phone(p_order.buyer_phone) is not null
     and i.deleted_at is null and i.status not in ('cancelled', 'refunded')
     and not exists (select 1 from public.web_orders w where w.invoice_id = i.id)
     and (public.normalize_customer_phone(c.phone) = public.normalize_customer_phone(p_order.buyer_phone)
          or exists (select 1 from public.event_guests g
                      where g.invoice_id = i.id and g.event_id = p_channel.event_id and g.source = 'ticket'
                        and public.normalize_customer_phone(g.phone) = public.normalize_customer_phone(p_order.buyer_phone)))
$f$;

-- Whether a Manager may link an order to an invoice made by hand: a recorded
-- or waiting order, or a staff-link registration refused because the channel
-- was off (staff are told to invoice those by hand).
create or replace function public.web_order_can_link(p_order public.web_orders)
returns boolean language sql stable set search_path to 'public' as $f$
  select p_order.status in ('recorded', 'needs_review')
      or (p_order.provider = 'door' and p_order.status = 'refused' and p_order.review_reason = 'The website channel is off')
$f$;

-- The people of an order that has no invoice: the names it was given (or the
-- buyer and placeholders), on its pass's days; cancelled when it was dismissed.
create or replace function public.web_order_sync_people(p_order public.web_orders, p_channel public.web_order_channels)
returns jsonb language sql stable security definer set search_path to 'public' as $f$
  select coalesce(jsonb_agg(jsonb_build_object(
           'position', t.k, 'name', t.p->>'name', 'phone', t.p->>'phone',
           'email', coalesce(nullif(btrim(p_order.attendees -> (t.k::integer - 1) ->> 'email'), ''),
                             case when t.k = 1 then p_order.buyer_email end),
           'days', coalesce((select jsonb_agg(to_char((d #>> '{}')::date, 'YYYY-MM-DD') order by (d #>> '{}')::date)
                               from jsonb_array_elements(case when jsonb_typeof(p_channel.ticket_map -> p_order.ticket -> 'days') = 'array'
                                                              then p_channel.ticket_map -> p_order.ticket -> 'days' end) d), '[]'::jsonb),
           'status', case when p_order.status = 'dismissed' then 'cancelled' else 'registered' end) order by t.k), '[]'::jsonb)
    from jsonb_array_elements(public.web_order_people(p_order, null)) with ordinality t(p, k)
$f$;

-- The invoice a Manager links an order to, by its number. Raises why it
-- cannot be: the order must be recorded or waiting (or a staff-link
-- registration refused while the channel was off); the invoice must exist,
-- not be deleted, cancelled or refunded, be at a store the Manager works in,
-- carry a ticket to the channel's event, and be no other website order's.
create or replace function public.web_order_link_target(p_order public.web_orders, p_channel public.web_order_channels,
  p_invoice_no text)
returns uuid language plpgsql stable security definer set search_path to 'public' as $f$
declare inv public.invoices%rowtype; v_other text;
begin
  if not public.web_order_can_link(p_order) then
    raise exception 'Only a recorded or waiting order, or a staff-link registration refused while the channel was off, can be linked to an invoice'; end if;
  select * into inv from public.invoices where invoice_no = upper(btrim(coalesce(p_invoice_no, '')));
  if not found or inv.deleted_at is not null then
    raise exception 'Invoice % was not found', btrim(coalesce(p_invoice_no, '')); end if;
  if not public.user_has_store_access(inv.store_id) then
    raise exception 'You do not have access to invoice %', inv.invoice_no; end if;
  if inv.status in ('cancelled', 'refunded') then
    raise exception 'Invoice % is %, so an order cannot be linked to it', inv.invoice_no, inv.status; end if;
  if not exists (select 1 from public.invoice_items ii
                   join public.event_ticket_options eo on eo.id = ii.event_ticket_option_id
                  where ii.invoice_id = inv.id and ii.line_kind = 'event_ticket' and eo.event_id = p_channel.event_id) then
    raise exception 'Invoice % has no ticket to %', inv.invoice_no, (select name from public.events where id = p_channel.event_id); end if;
  select w.stripe_session_id into v_other from public.web_orders w
   where w.invoice_id = inv.id and w.id <> p_order.id order by w.created_at limit 1;
  if v_other is not null then
    raise exception 'Invoice % is already the invoice of website order %', inv.invoice_no, v_other; end if;
  return inv.id;
end $f$;

-- What a Manager sees before linking, and what the audit keeps after.
create or replace function public.web_order_link_summary(p_order public.web_orders, p_channel public.web_order_channels,
  p_invoice_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $f$
declare inv public.invoices%rowtype; v_people integer; v_warn text[] := '{}';
begin
  select * into inv from public.invoices where id = p_invoice_id;
  select count(*) into v_people from public.event_guests g
   where g.invoice_id = inv.id and g.event_id = p_channel.event_id and g.source = 'ticket' and g.status = 'registered';
  if inv.total_amount <> round(p_order.amount_total_cents / 100.0, 2) then
    v_warn := v_warn || format('The invoice total is S$%s, but the order is for S$%s',
      to_char(inv.total_amount, 'FM999990.00'), to_char(p_order.amount_total_cents / 100.0, 'FM999990.00')); end if;
  if inv.paid_amount < inv.total_amount then
    v_warn := v_warn || format('The invoice is not fully paid: S$%s of S$%s',
      to_char(inv.paid_amount, 'FM999990.00'), to_char(inv.total_amount, 'FM999990.00')); end if;
  if v_people <> p_order.quantity then
    v_warn := v_warn || format('The invoice has %s people for this event, and the order %s', v_people, p_order.quantity); end if;
  if inv.store_id <> p_channel.store_id then
    v_warn := v_warn || format('The invoice is at %s, not at the event''s store %s',
      (select name from public.stores where id = inv.store_id), (select name from public.stores where id = p_channel.store_id)); end if;
  return jsonb_build_object('invoice_no', inv.invoice_no, 'store', (select name from public.stores where id = inv.store_id),
    'date', inv.business_date, 'customer_name', (select full_name from public.customers where id = inv.customer_id),
    'total', inv.total_amount, 'paid', inv.paid_amount, 'methods', public.web_order_invoice_methods(inv.id),
    'people', v_people, 'warnings', to_jsonb(v_warn));
end $f$;

-- ── 3. Making the invoice ──────────────────────────────────────────────────
-- 376's web_order_make_invoice, with staff-link orders: only a Manager makes
-- their invoice (web_order_resolve), with no payment-gateway time rules,
-- dated on the date paid, paid with the form's method and reference, and
-- crediting the staff member who registered them. Online orders are made
-- exactly as before.
create or replace function public.web_order_make_invoice(p_order_id uuid, p_customer_id uuid default null,
  p_new_customer boolean default false, p_reviewed boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare
  o public.web_orders%rowtype; ch public.web_order_channels%rowtype; v_prev text;
  v_customer uuid; v_map jsonb; v_items jsonb; v_inv uuid; v_total numeric; v_paid date; v_reason text; v_state text;
  v_times text; v_line uuid; v_name text; v_method uuid;
  v_door boolean; v_staff uuid; v_today date := (now() at time zone 'Asia/Singapore')::date;
begin
  select * into o from public.web_orders where id = p_order_id for update;
  if not found then raise exception 'Website order not found'; end if;
  if o.status = 'invoiced' then
    return jsonb_build_object('status', 'invoiced', 'invoice_no', (select invoice_no from public.invoices where id = o.invoice_id),
                              'review_reason', null);
  end if;
  -- 380: a staff-link order is invoiced only when an Owner, Admin or Manager
  -- creates its invoice (the caller, before this acts as the channel's
  -- profile), never on its own; a dismissed one not at all.
  v_door := o.provider = 'door';
  if v_door and (o.status = 'dismissed' or not public.is_manager_or_above()) then
    return jsonb_build_object('status', o.status, 'invoice_no', null, 'review_reason', o.review_reason);
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
    -- which web_order_resolve looks for. 380: not for a staff-link order,
    -- whose times are the form's and were checked on arrival.
    if not p_reviewed and not v_door then
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
    if v_door then
      -- 380: the channel's method for the form's choice, active.
      select pm.id into v_method from public.payment_methods pm
       where pm.id = nullif(ch.door_methods ->> o.door_method, '')::uuid and pm.is_active and pm.deleted_at is null;
      if v_method is null then
        raise exception 'WEB_ORDER_REVIEW: This channel has no active % payment method, so nothing was invoiced',
          public.web_order_door_method_name(o.door_method); end if;
      v_staff := case when public.web_order_seller(o.staff_profile_id) then o.staff_profile_id end;
    else
      -- 376: the provider's payment method, before anything is made.
      v_method := public.web_order_payment_method(ch, o.provider);
      if v_method is null then
        raise exception 'WEB_ORDER_REVIEW: The website has no payment method for % orders', v_name; end if;
    end if;
    v_customer := public.web_order_customer(o, ch, p_customer_id, p_new_customer);
    v_items := jsonb_build_array(jsonb_build_object(
      'kind', 'event_ticket', 'event_ticket_option_id', v_map->>'option_id', 'quantity', o.quantity,
      'event_days', coalesce(v_map->'days', '[]'::jsonb),
      'attendees', public.web_order_people(o, v_customer)));
    if v_door then
      -- 380: dated on the date paid (so the early bird follows it), never
      -- after today; the staff member who registered them is its service staff.
      v_inv := public.create_invoice_with_details(ch.store_id, v_customer, v_items, jsonb_build_object(
        'business_date', least(o.paid_on, v_today)::text,
        'notes', 'Website staff link · ' || o.stripe_session_id || ' · ' || public.web_order_door_method_name(o.door_method)
                 || case when o.early_bird then ' · early bird' else '' end,
        'manual_discount', 0,
        'service_staff', case when v_staff is not null then jsonb_build_array(v_staff) else '[]'::jsonb end));
    else
      -- 373: never dated after today.
      v_inv := public.create_invoice_with_details(ch.store_id, v_customer, v_items, jsonb_build_object(
        'business_date', least((o.checkout_opened_at at time zone 'Asia/Singapore')::date,
                               (now() at time zone 'Asia/Singapore')::date)::text,
        'notes', 'Website order · ' || v_name || ' ' || o.stripe_session_id || case when o.early_bird then ' · early bird' else '' end,
        'manual_discount', 0));
    end if;
    select total_amount into v_total from public.invoices where id = v_inv;
    if v_total <> round(o.amount_total_cents / 100.0, 2) then
      if v_door then
        raise exception 'WEB_ORDER_REVIEW: The invoice would be S$% but S$% was paid, so nothing was invoiced',
          to_char(v_total, 'FM999990.00'), to_char(o.amount_total_cents / 100.0, 'FM999990.00'); end if;
      raise exception 'WEB_ORDER_REVIEW: The invoice would be S$% but % charged S$%, so nothing was invoiced',
        to_char(v_total, 'FM999990.00'), v_name, to_char(o.amount_total_cents / 100.0, 'FM999990.00'); end if;
    v_paid := case when v_door then least(o.paid_on, v_today)
                   else least((o.paid_at at time zone 'Asia/Singapore')::date, (now() at time zone 'Asia/Singapore')::date) end;
    if v_total > 0 then
      perform public.record_invoice_payment(v_inv, jsonb_build_array(jsonb_build_object(
        'payment_method_id', v_method, 'amount', v_total,
        'reference', case when v_door then coalesce(o.payment_reference, o.stripe_session_id)
                          else coalesce(o.stripe_payment_intent, o.stripe_session_id) end,
        'payment_date', v_paid)),
        public.web_order_uuid('web-order-payment:' || o.stripe_session_id));
    end if;
    -- 373: the ticket line this order made (the invoice has only this one).
    select ii.id into v_line from public.invoice_items ii
     where ii.invoice_id = v_inv and ii.line_kind = 'event_ticket' limit 1;
    -- 380: the staff member who registered them registered its guests.
    if v_staff is not null then
      update public.event_guests set registered_by = v_staff where invoice_id = v_inv;
    end if;
    update public.web_orders
       set status = 'invoiced', invoice_id = v_inv, invoice_item_id = v_line, customer_id = v_customer, review_reason = null,
           candidate_customer_ids = '{}', updated_at = now()
     where id = o.id;
    -- 380: its people keep the numbers the website gave them, whatever is
    -- changed on the invoice later.
    perform public.web_order_number_people(ch.event_id, v_inv);
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

-- ── 4. What the website hands in and asks for (service role only) ──────────

-- A staff-link registration. Kept once per OFF id, never invoiced here (a
-- Manager creates its invoice); a repeat returns what was kept and changes
-- nothing. Returns {status, invoice_no, review_reason}.
create or replace function public.web_order_door(p_order jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare ch public.web_order_channels%rowtype; o public.web_orders%rowtype; v public.web_orders%rowtype;
  v_id text; v_qty integer;
begin
  v_id := p_order->>'order_id';
  if v_id is null or v_id !~ '^OFF-[0-9]{8}-[0-9A-F]{6}$' then
    return jsonb_build_object('status', 'refused', 'invoice_no', null, 'review_reason', 'Not a staff-link order id'); end if;
  if coalesce(p_order->>'provider', 'door') <> 'door' then
    return jsonb_build_object('status', 'refused', 'invoice_no', null, 'review_reason', 'Unknown payment provider'); end if;
  select * into ch from public.web_order_channels where key = p_order->>'channel';
  if not found then
    return jsonb_build_object('status', 'refused', 'invoice_no', null, 'review_reason', 'Unknown website channel'); end if;
  v_qty := (p_order->>'quantity')::integer;
  if coalesce(p_order->>'ticket', '') = '' or coalesce(v_qty, 0) not between 1 and 10
     or coalesce((p_order->>'amount_total_cents')::integer, -1) not between 0 and 10000000
     or nullif(p_order->>'paid_on', '') is null or nullif(p_order->>'registered_at', '') is null
     or coalesce(p_order->>'method', '') not in ('cash', 'paynow', 'bank')
     or length(btrim(coalesce(p_order->>'reference', ''))) > 100
     or coalesce(btrim(p_order->'buyer'->>'first_name'), '') = ''
     or jsonb_typeof(p_order->'attendees') is distinct from 'array' then
    return jsonb_build_object('status', 'refused', 'invoice_no', null, 'review_reason', 'The order is incomplete'); end if;
  if jsonb_array_length(p_order->'attendees') <> v_qty
     or exists (select 1 from jsonb_array_elements(p_order->'attendees') x where coalesce(btrim(x->>'name'), '') = '') then
    return jsonb_build_object('status', 'refused', 'invoice_no', null, 'review_reason', 'The order is incomplete'); end if;

  -- The order as it is kept: the OFF id where a checkout id goes, the
  -- registration time as the checkout's and the payment's, and the names
  -- as 'names' keeps them.
  v.channel := ch.key; v.provider := 'door'; v.stripe_session_id := v_id; v.livemode := true;
  v.ticket := p_order->>'ticket'; v.quantity := v_qty;
  v.amount_total_cents := (p_order->>'amount_total_cents')::integer;
  v.unit_amount_cents := round(v.amount_total_cents::numeric / v_qty)::integer;
  v.paid_on := (p_order->>'paid_on')::date;
  v.checkout_opened_at := (p_order->>'registered_at')::timestamptz; v.paid_at := v.checkout_opened_at;
  -- The early bird follows the date paid, by the event's own rule.
  v.early_bird := coalesce((select e.early_bird_until is not null and v.paid_on <= e.early_bird_until
                              from public.events e where e.id = ch.event_id), false);
  v.buyer_first_name := btrim(p_order->'buyer'->>'first_name');
  v.buyer_last_name := nullif(btrim(coalesce(p_order->'buyer'->>'last_name', '')), '');
  v.buyer_name := public.join_person_name(v.buyer_first_name, v.buyer_last_name);
  v.buyer_email := nullif(btrim(coalesce(p_order->'buyer'->>'email', '')), '');
  v.buyer_phone := nullif(btrim(coalesce(p_order->'buyer'->>'whatsapp', '')), '');
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('name', btrim(x->>'name'),
           'email', nullif(btrim(coalesce(x->>'email', '')), ''), 'whatsapp', nullif(btrim(coalesce(x->>'whatsapp', '')), ''))) order by k)
    into v.attendees from jsonb_array_elements(p_order->'attendees') with ordinality t(x, k);
  v.door_method := p_order->>'method';
  v.payment_reference := nullif(btrim(coalesce(p_order->>'reference', '')), '');
  v.staff_profile_id := nullif(p_order->>'staff_id', '')::uuid;

  -- One at a time per channel, so two registrations of one person arriving
  -- together see each other.
  perform pg_advisory_xact_lock(hashtextextended('web-order-door:' || ch.key, 0));
  if ch.mode = 'off' then
    v.status := 'refused'; v.review_reason := 'The website channel is off';
  else
    v.review_reason := public.web_order_door_review(v, ch);
    v.status := case when v.review_reason is null then 'recorded' else 'needs_review' end;
  end if;
  -- Registered by credits only active staff (the review said so otherwise).
  if not public.web_order_seller(v.staff_profile_id) then v.staff_profile_id := null; end if;

  insert into public.web_orders
    (channel, provider, stripe_session_id, stripe_payment_intent, livemode, status, ticket, quantity, unit_amount_cents,
     amount_total_cents, early_bird, buyer_name, buyer_email, buyer_phone, checkout_opened_at, paid_at, attendees, names_at,
     buyer_first_name, buyer_last_name, review_reason, door_method, payment_reference, staff_profile_id, paid_on)
  values (v.channel, v.provider, v.stripe_session_id, null, v.livemode, v.status, v.ticket, v.quantity, v.unit_amount_cents,
          v.amount_total_cents, v.early_bird, v.buyer_name, v.buyer_email, v.buyer_phone, v.checkout_opened_at, v.paid_at,
          v.attendees, now(), v.buyer_first_name, v.buyer_last_name, v.review_reason, v.door_method, v.payment_reference,
          v.staff_profile_id, v.paid_on)
  on conflict (stripe_session_id) do nothing;
  select * into o from public.web_orders where stripe_session_id = v_id for update;
  if o.channel <> ch.key then
    return jsonb_build_object('status', 'refused', 'invoice_no', null, 'review_reason', 'The order belongs to another channel'); end if;
  if o.provider <> 'door' then
    return jsonb_build_object('status', 'refused', 'invoice_no', null, 'review_reason', 'The order belongs to another payment provider'); end if;
  return jsonb_build_object('status', o.status,
    'invoice_no', (select invoice_no from public.invoices where id = o.invoice_id), 'review_reason', o.review_reason);
end $f$;

-- What the website's sheet needs: the event, every website and staff-link
-- order (not refused, not test) with its invoice and people, and every
-- invoice that sold tickets to the event at the counter (no website order's),
-- deleted ones too once a sync has listed them (invoice_status 'deleted',
-- their people cancelled). People come by their numbers on the sheet, given
-- here the first time. At most once a minute per channel: sooner is
-- 'too_soon', with nothing else.
create or replace function public.web_order_sync(p_channel text)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare ch public.web_order_channels%rowtype;
begin
  -- One sync at a time per channel. Not FOR UPDATE: every new web order
  -- takes a key-share lock on its channel, which that would wait for.
  select * into ch from public.web_order_channels where key = p_channel for no key update;
  if not found then return jsonb_build_object('status', 'refused'); end if;
  if ch.last_sync_at > now() - interval '60 seconds' then return jsonb_build_object('status', 'too_soon'); end if;
  update public.web_order_channels set last_sync_at = now() where key = ch.key;
  perform public.web_order_number_people(ch.event_id, null);
  return jsonb_build_object(
    'status', 'ok',
    'event', (select jsonb_build_object('name', e.name,
                       'days', coalesce((select jsonb_agg(to_char(d.day, 'YYYY-MM-DD') order by d.day)
                                           from public.event_days d where d.event_id = e.id), '[]'::jsonb))
                from public.events e where e.id = ch.event_id),
    'orders', coalesce((
      select jsonb_agg(jsonb_build_object(
               'order_id', o.stripe_session_id, 'provider', o.provider, 'status', o.status,
               'invoice_no', i.invoice_no,
               'invoice_status', case when i.id is null then null when i.deleted_at is not null then 'deleted' else i.status::text end,
               'date', to_char(coalesce(o.paid_on, (o.paid_at at time zone 'Asia/Singapore')::date), 'YYYY-MM-DD'),
               'buyer_name', o.buyer_name, 'buyer_phone', o.buyer_phone, 'buyer_email', o.buyer_email,
               'ticket', o.ticket, 'quantity', o.quantity,
               'method', case when o.provider = 'door' then public.web_order_door_method_name(o.door_method)
                              else public.web_order_provider_name(o.provider) end,
               'reference', case when o.provider = 'door' then o.payment_reference else o.stripe_payment_intent end,
               'staff_name', sp.full_name,
               'people', case when i.id is not null then public.web_order_invoice_people(i.id, ch.event_id, o, false)
                              else public.web_order_sync_people(o, ch) end)
             order by o.paid_at, o.created_at)
        from public.web_orders o
        left join public.invoices i on i.id = o.invoice_id
        left join public.profiles sp on sp.id = o.staff_profile_id
       where o.channel = ch.key and o.status <> 'refused' and o.livemode), '[]'::jsonb),
    'counter', coalesce((
      select jsonb_agg(jsonb_build_object(
               'invoice_no', i.invoice_no,
               'invoice_status', case when i.deleted_at is not null then 'deleted' else i.status::text end,
               'date', to_char(i.business_date, 'YYYY-MM-DD'),
               'customer_name', c.full_name, 'phone', c.phone, 'email', c.email,
               'methods', public.web_order_invoice_methods(i.id),
               'staff_name', coalesce((select string_agg(p.full_name, ', ' order by p.full_name)
                                         from public.invoice_service_staff ss join public.profiles p on p.id = ss.staff_id
                                        where ss.invoice_id = i.id),
                                      (select p.full_name from public.profiles p where p.id = i.created_by)),
               'people', public.web_order_invoice_people(i.id, ch.event_id, null, true))
             order by i.business_date, i.invoice_no)
        from public.invoices i
        left join public.customers c on c.id = i.customer_id
       where (i.deleted_at is null
              or exists (select 1 from public.web_order_sync_positions n where n.event_id = ch.event_id and n.invoice_id = i.id))
         and i.id in (select g.invoice_id from public.event_guests g
                       where g.event_id = ch.event_id and g.source = 'ticket' and g.invoice_id is not null)
         and not exists (select 1 from public.web_orders w where w.invoice_id = i.id)), '[]'::jsonb));
end $f$;

-- The staff the website's form may offer as Registered by: active staff whom
-- an invoice takes as service staff, by name. Name and id only.
create or replace function public.web_order_staff(p_channel text)
returns jsonb language sql stable security definer set search_path to 'public' as $f$
  select case when not exists (select 1 from public.web_order_channels where key = p_channel)
              then jsonb_build_object('status', 'refused', 'staff', '[]'::jsonb)
              else jsonb_build_object('status', 'ok', 'staff', coalesce((
                     select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.full_name) order by lower(p.full_name), p.id)
                       from public.profiles p
                      where public.web_order_seller(p.id) and btrim(p.full_name) <> ''), '[]'::jsonb)) end
$f$;

-- 373's web_order_names, leaving staff-link orders alone: their names come
-- with them, and nothing but a Manager invoices them.
create or replace function public.web_order_names(p_order jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare ch public.web_order_channels%rowtype; o public.web_orders%rowtype; v_att jsonb; v_note text; v_same boolean;
begin
  select * into o from public.web_orders
   where stripe_session_id = p_order->>'stripe_session_id' and channel = p_order->>'channel'
     and provider <> 'door'  -- 380
     for update;
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

-- ── 5. What the Events page calls (Owner, Admin, Manager) ──────────────────

-- 376's web_order_resolve: a dismissed order is restored before its invoice
-- is made.
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
  -- 380
  if o.status = 'dismissed' then raise exception 'A dismissed order is not invoiced. Restore it first'; end if;
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

-- 376's web_orders_list, with each staff-link order's method, reference, date
-- paid and the staff member who registered it, and, for an order that can
-- still be linked, the invoices made by hand that may already be its own.
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
               'created_at', o.created_at,
               -- 380: a staff-link order's form.
               'door_method', o.door_method, 'payment_reference', o.payment_reference, 'paid_on', o.paid_on,
               'staff_profile_id', o.staff_profile_id,
               'staff_name', (select full_name from public.profiles where id = o.staff_profile_id),
               'hand_invoices', case when public.web_order_can_link(o) then public.web_order_hand_invoices(o, ch)
                                     else '[]'::jsonb end)
             order by o.paid_at desc, o.created_at desc)
        from public.web_orders o left join public.invoices i on i.id = o.invoice_id
       where o.channel = ch.key), '[]'));
end $f$;

-- What linking an order to an invoice would do: the invoice, and what does
-- not match. Read-only; refuses what web_order_link_invoice refuses.
create or replace function public.web_order_link_preview(p_order_id uuid, p_invoice_no text)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $f$
declare o public.web_orders%rowtype; ch public.web_order_channels%rowtype;
begin
  if not public.is_manager_or_above() then raise exception 'Only an Owner, Admin or Manager can link a website order to an invoice'; end if;
  select * into o from public.web_orders where id = p_order_id;
  if not found then raise exception 'Website order not found'; end if;
  select * into ch from public.web_order_channels where key = o.channel;
  if not public.user_has_store_access(ch.store_id) then raise exception 'You do not have access to this event''s store'; end if;
  return public.web_order_link_summary(o, ch, public.web_order_link_target(o, ch, p_invoice_no));
end $f$;

-- Links a recorded or waiting order (or a staff-link registration refused
-- while the channel was off) to an invoice made by hand, instead of making a
-- second one: the order is then that invoice's, for that invoice's customer.
-- The invoice and its guests are not changed. Audited.
create or replace function public.web_order_link_invoice(p_order_id uuid, p_invoice_no text)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare o public.web_orders%rowtype; ch public.web_order_channels%rowtype; v_inv uuid; v_lines uuid[]; v_summary jsonb;
begin
  if not public.is_manager_or_above() then raise exception 'Only an Owner, Admin or Manager can link a website order to an invoice'; end if;
  select * into o from public.web_orders where id = p_order_id for update;
  if not found then raise exception 'Website order not found'; end if;
  select * into ch from public.web_order_channels where key = o.channel;
  if not public.user_has_store_access(ch.store_id) then raise exception 'You do not have access to this event''s store'; end if;
  -- The invoice first, so two orders cannot take one invoice at once; then
  -- every check, on what is there now.
  perform 1 from public.invoices where invoice_no = upper(btrim(coalesce(p_invoice_no, ''))) for update;
  v_inv := public.web_order_link_target(o, ch, p_invoice_no);
  v_summary := public.web_order_link_summary(o, ch, v_inv);
  select coalesce(array_agg(ii.id), '{}') into v_lines from public.invoice_items ii
    join public.event_ticket_options eo on eo.id = ii.event_ticket_option_id
   where ii.invoice_id = v_inv and ii.line_kind = 'event_ticket' and eo.event_id = ch.event_id;
  update public.web_orders
     set status = 'invoiced', invoice_id = v_inv,
         invoice_item_id = case when cardinality(v_lines) = 1 then v_lines[1] end,
         customer_id = (select customer_id from public.invoices where id = v_inv),
         review_reason = null, candidate_customer_ids = '{}', updated_at = now()
   where id = o.id;
  -- Its people keep the numbers they have on the website's sheet from now on.
  perform public.web_order_number_people(ch.event_id, v_inv);
  perform public.write_audit_ex('web_orders', o.id, 'web_order_linked',
    jsonb_build_object('status', o.status, 'review_reason', o.review_reason, 'invoice_id', o.invoice_id),
    v_summary || jsonb_build_object('status', 'invoiced', 'invoice_id', v_inv, 'order_id', o.stripe_session_id),
    'events', null, ch.store_id);
  return jsonb_build_object('status', 'invoiced', 'invoice_no', v_summary->>'invoice_no');
end $f$;

-- Dismisses a staff-link registration that is not a sale (a test), with the
-- reason, or (p_dismiss false) restores it: recorded again, or waiting if
-- the arrival checks now find a reason. Audited.
create or replace function public.web_order_dismiss(p_order_id uuid, p_reason text, p_dismiss boolean default true)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare o public.web_orders%rowtype; ch public.web_order_channels%rowtype; n public.web_orders%rowtype;
  v_reason text;
begin
  if not public.is_manager_or_above() then raise exception 'Only an Owner, Admin or Manager can dismiss a website order'; end if;
  select * into o from public.web_orders where id = p_order_id for update;
  if not found then raise exception 'Website order not found'; end if;
  select * into ch from public.web_order_channels where key = o.channel;
  if not public.user_has_store_access(ch.store_id) then raise exception 'You do not have access to this event''s store'; end if;
  if o.provider <> 'door' then raise exception 'Only a staff-link registration can be dismissed'; end if;
  if coalesce(p_dismiss, true) then
    if o.status not in ('recorded', 'needs_review') then
      raise exception 'Only a recorded or waiting registration can be dismissed'; end if;
    if length(btrim(coalesce(p_reason, ''))) < 3 then
      raise exception 'Give the reason for dismissing it (at least 3 characters)'; end if;
    update public.web_orders
       set status = 'dismissed', review_reason = btrim(p_reason), candidate_customer_ids = '{}', updated_at = now()
     where id = o.id returning * into n;
  else
    if o.status <> 'dismissed' then raise exception 'Only a dismissed registration can be restored'; end if;
    v_reason := public.web_order_door_review(o, ch);
    update public.web_orders
       set status = case when v_reason is null then 'recorded' else 'needs_review' end, review_reason = v_reason,
           staff_profile_id = case when public.web_order_seller(staff_profile_id) then staff_profile_id end,
           updated_at = now()
     where id = o.id returning * into n;
  end if;
  perform public.write_audit_ex('web_orders', o.id,
    case when coalesce(p_dismiss, true) then 'web_order_dismissed' else 'web_order_restored' end,
    jsonb_build_object('status', o.status, 'review_reason', o.review_reason),
    jsonb_build_object('status', n.status, 'review_reason', n.review_reason, 'order_id', o.stripe_session_id),
    'events', nullif(btrim(coalesce(p_reason, '')), ''), ch.store_id);
  return jsonb_build_object('status', n.status, 'invoice_no', null, 'review_reason', n.review_reason);
end $f$;

-- 370's event_guest_list, with each guest's email (the customer's, else the
-- one the website order gave for that person, while they still have the name
-- it gave), the website order whose invoice it is, and the invoice's payment
-- methods, for the Guests export.
-- Like the invoice, out of sight at a store the person does not work in.
create or replace function public.event_guest_list(p_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $f$
begin
  if not public.event_can_run(p_event_id) then raise exception 'You do not have access to this event'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'guest_id', g.id, 'name', g.name, 'phone', g.phone, 'customer_id', g.customer_id,
             'customer_name', c.full_name, 'source', g.source, 'status', g.status,
             'cancelled_reason', g.cancelled_reason, 'notes', g.notes,
             'registered_by', g.registered_by, 'registered_by_name', rb.full_name,
             'ticket_option_id', g.ticket_option_id, 'ticket_option_name', o.name,
             -- An invoice of a store the person does not work in stays out of sight.
             'invoice_id', case when i.id is not null and public.user_has_store_access(i.store_id) then g.invoice_id end,
             'invoice_no', case when i.id is not null and public.user_has_store_access(i.store_id) then i.invoice_no end,
             'invoice_status', i.status,
             'invoice_total', case when i.id is not null and public.user_has_store_access(i.store_id) then i.total_amount end,
             'invoice_paid', case when i.id is not null and public.user_has_store_access(i.store_id) then i.paid_amount end,
             'invoice_store_id', i.store_id,
             'created_at', g.created_at,
             -- 380
             'email', case when i.id is null or public.user_has_store_access(i.store_id)
                           then coalesce(nullif(btrim(c.email), ''), w.email) end,
             'order_id', case when i.id is not null and public.user_has_store_access(i.store_id) then w.order_id end,
             'payment_methods', case when i.id is not null and public.user_has_store_access(i.store_id)
                                     then public.web_order_invoice_methods(i.id) end,
             'days', coalesce((select jsonb_agg(jsonb_build_object('day', gd.day, 'attended_at', gd.attended_at,
                                  'check_in_code', gd.check_in_code, 'checked_in_by_name', cb.full_name) order by gd.day)
                                from public.event_guest_days gd left join public.profiles cb on cb.id = gd.checked_in_by
                               where gd.guest_id = g.id), '[]'))
           order by g.status, lower(g.name), g.created_at)
      from public.event_guests g
      left join public.customers c on c.id = g.customer_id
      left join public.profiles rb on rb.id = g.registered_by
      left join public.event_ticket_options o on o.id = g.ticket_option_id
      left join public.invoices i on i.id = g.invoice_id
      -- 380: the website order whose invoice it is, and the email it gave
      -- for this person (on the ticket line it made).
      left join lateral (select w2.stripe_session_id as order_id,
                                case when g.invoice_item_id = w2.invoice_item_id
                                     then public.web_order_person_email(w2, g.line_position, g.name) end as email
                           from public.web_orders w2
                          where g.invoice_id is not null and w2.invoice_id = g.invoice_id
                          order by w2.created_at limit 1) w on true
     where g.event_id = p_event_id), '[]');
end $f$;

-- ── 6. Who may call what ───────────────────────────────────────────────────
-- The replaced functions keep their grants. The rules are for these functions
-- only; the website's three are for the service role (the edge function).
revoke all on function public.web_order_door_method_name(text) from public, anon, authenticated;
revoke all on function public.web_order_seller(uuid) from public, anon, authenticated;
revoke all on function public.web_order_door_review(public.web_orders, public.web_order_channels) from public, anon, authenticated;
revoke all on function public.web_order_invoice_methods(uuid) from public, anon, authenticated;
revoke all on function public.web_order_person_email(public.web_orders, integer, text) from public, anon, authenticated;
revoke all on function public.web_order_number_people(uuid, uuid) from public, anon, authenticated;
revoke all on function public.web_order_invoice_people(uuid, uuid, public.web_orders, boolean) from public, anon, authenticated;
revoke all on function public.web_order_hand_invoices(public.web_orders, public.web_order_channels) from public, anon, authenticated;
revoke all on function public.web_order_can_link(public.web_orders) from public, anon, authenticated;
revoke all on function public.web_order_sync_people(public.web_orders, public.web_order_channels) from public, anon, authenticated;
revoke all on function public.web_order_link_target(public.web_orders, public.web_order_channels, text) from public, anon, authenticated;
revoke all on function public.web_order_link_summary(public.web_orders, public.web_order_channels, uuid) from public, anon, authenticated;
revoke all on function public.web_order_door(jsonb) from public, anon, authenticated;
revoke all on function public.web_order_sync(text) from public, anon, authenticated;
revoke all on function public.web_order_staff(text) from public, anon, authenticated;
grant execute on function public.web_order_door_method_name(text), public.web_order_seller(uuid),
  public.web_order_door_review(public.web_orders, public.web_order_channels), public.web_order_invoice_methods(uuid),
  public.web_order_person_email(public.web_orders, integer, text), public.web_order_number_people(uuid, uuid),
  public.web_order_invoice_people(uuid, uuid, public.web_orders, boolean),
  public.web_order_hand_invoices(public.web_orders, public.web_order_channels), public.web_order_can_link(public.web_orders),
  public.web_order_sync_people(public.web_orders, public.web_order_channels),
  public.web_order_link_target(public.web_orders, public.web_order_channels, text),
  public.web_order_link_summary(public.web_orders, public.web_order_channels, uuid),
  public.web_order_door(jsonb), public.web_order_sync(text), public.web_order_staff(text) to service_role;

revoke all on function public.web_order_link_preview(uuid, text) from public, anon;
revoke all on function public.web_order_link_invoice(uuid, text) from public, anon;
revoke all on function public.web_order_dismiss(uuid, text, boolean) from public, anon;
grant execute on function public.web_order_link_preview(uuid, text), public.web_order_link_invoice(uuid, text),
  public.web_order_dismiss(uuid, text, boolean) to authenticated, service_role;

notify pgrst, 'reload schema';
