-- 370_events.sql
--
-- EVENTS (asked for on 29 Sep 2026; the owner's rules, as answered that day)
--
--   An event runs on one or more days at one or more stores, for example a
--   two-day birthday event at the roadshow van. It sells tickets: each ticket
--   option covers a number of the event's days (a "1 day" ticket, a "2 days"
--   ticket) at a price per person, with an optional early-bird discount for
--   invoices dated on or before a cut-off day.
--
--   1. A ticket is bought on an invoice, as an event_ticket line (369): the
--      option, the day(s) it covers (a 1-day ticket of a 2-day event names its
--      day), and the number of people. Every person is named. The price comes
--      from the option and the invoice's business date: on or before the
--      early-bird day it is the early-bird price, after it the full price. An
--      invoice dated back into the early bird after it has ended gets that
--      price only when an Owner, Admin or Manager saves it.
--      A line voucher cannot discount a ticket; a manual discount, an invoice
--      discount voucher and FOC work as on any line. A ticket goes on an
--      invoice at any store (an early-bird ticket can be bought elsewhere
--      before the event). Once the event is off sale or over, a saved ticket
--      can still be corrected, but no one can be added to it.
--   2. Every person on a ticket is a guest of the event, with the ticket's
--      days. Staff can also add free guests (their days, the staff member who
--      registered them, notes such as a dietary need or a door gift). A guest
--      is checked in day by day, with an optional code for the day.
--   3. An invoice is an event sale when it is dated on an event day at one of
--      the event's stores, or holds a ticket to it. Staff can mark any invoice
--      of their store as a sale of an event, or as no event sale, and undo it.
--   4. A day can have a capacity. A full day warns and never refuses.
--   5. Owners, Admins and Managers set up events, at the stores they work in
--      (a store they do not work in stays on the event as it is). Anyone who
--      works at one of an event's stores keeps its guest list and checks
--      people in; invoices of other stores stay out of their sight.
--   6. Tickets earn commission like any other sale and count toward therapy
--      qualification, with no change. Wallet credit pays for tickets where the
--      credit allows it: a new spending category, event_ticket, which general
--      credit allows and a credit package allows when the Owner ticks it; old
--      credit whose purposes list "event" keeps allowing it.
--
-- A ticket's guests follow the invoice: a line's people are the line's
-- guests, one named person per person paid for; a line taken off the
-- invoice, a line refunded in full, or an invoice cancelled, refunded or
-- deleted, cancels them, and undoing that (a reopen) restores them. To take
-- one person off a paid ticket, correct the invoice, then refund. Every change
-- to a ticket's people is in the audit log. Ticket money in the report and on
-- an event's sales is the line's share of the invoice after discounts, less
-- refunds.
--
-- SAFETY: every patched function is guarded by the md5 of its production
-- version (29 Sep 2026) and by anchors that must occur exactly once; a
-- function already carrying "370:" is left alone. Nothing existing is
-- dropped, and no existing row is changed.

set lock_timeout = '5s';

do $$ begin
  if not exists (select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
                  join pg_namespace n on n.oid = t.typnamespace
                  where n.nspname = 'public' and t.typname = 'invoice_line_kind'
                    and e.enumlabel = 'event_ticket') then
    raise exception '370: apply 369 first (invoice_line_kind has no event_ticket)'; end if;
end $$;

-- ── 1. What an event is ────────────────────────────────────────────────────
create table if not exists public.events (
  id                 uuid primary key default gen_random_uuid(),
  name               text not null,
  description        text,
  daily_start        time,
  daily_end          time,
  early_bird_until   date,           -- the last business date with the early-bird price
  early_bird_percent numeric(5,2),   -- off the option's price, per person
  is_active          boolean not null default true,
  notes              text,
  created_by         uuid references public.profiles(id) on delete set null,
  created_at         timestamptz not null default now(),
  updated_by         uuid references public.profiles(id) on delete set null,
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz,
  constraint events_name_given check (btrim(name) <> ''),
  constraint events_early_bird_whole check ((early_bird_until is null) = (early_bird_percent is null)),
  constraint events_early_bird_percent check (early_bird_percent is null or (early_bird_percent > 0 and early_bird_percent <= 100)),
  constraint events_hours check (daily_start is null or daily_end is null or daily_end > daily_start)
);

create table if not exists public.event_days (
  event_id uuid not null references public.events(id) on delete cascade,
  day      date not null,
  capacity integer,
  primary key (event_id, day),
  constraint event_days_capacity check (capacity is null or capacity > 0)
);

-- The stores whose invoices on an event day are the event's sales.
create table if not exists public.event_stores (
  event_id uuid not null references public.events(id) on delete cascade,
  store_id uuid not null references public.stores(id),
  primary key (event_id, store_id)
);
create index if not exists event_stores_store_idx on public.event_stores(store_id);

create table if not exists public.event_ticket_options (
  id         uuid primary key default gen_random_uuid(),
  event_id   uuid not null references public.events(id) on delete cascade,
  name       text not null,
  days_count integer not null,
  price      numeric(12,2) not null,
  is_active  boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint event_ticket_options_name_given check (btrim(name) <> ''),
  constraint event_ticket_options_days check (days_count >= 1),
  constraint event_ticket_options_price check (price >= 0)
);
create index if not exists event_ticket_options_event_idx on public.event_ticket_options(event_id);

-- A ticket line names its option and the day(s) it covers.
alter table public.invoice_items
  add column if not exists event_ticket_option_id uuid references public.event_ticket_options(id),
  add column if not exists event_days date[];
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'invoice_item_event_ticket_whole'
                   and conrelid = 'public.invoice_items'::regclass) then
    alter table public.invoice_items add constraint invoice_item_event_ticket_whole check (
      (line_kind = 'event_ticket') = (event_ticket_option_id is not null)
      and (line_kind <> 'event_ticket' or coalesce(cardinality(event_days), 0) > 0));
  end if;
end $$;
create index if not exists invoice_items_event_ticket_option_idx
  on public.invoice_items(event_ticket_option_id) where event_ticket_option_id is not null;

-- Everyone on the guest list: the people on ticket lines and free guests.
create table if not exists public.event_guests (
  id               uuid primary key default gen_random_uuid(),
  event_id         uuid not null references public.events(id),
  name             text not null,
  phone            text,
  customer_id      uuid references public.customers(id) on delete set null,
  source           text not null,
  invoice_id       uuid references public.invoices(id) on delete cascade,
  invoice_item_id  uuid,            -- the ticket line; kept after the line is removed
  ticket_option_id uuid references public.event_ticket_options(id) on delete set null,
  line_position    integer,
  registered_by    uuid references public.profiles(id) on delete set null,
  notes            text,
  status           text not null default 'registered',
  cancelled_reason text,
  cancelled_at     timestamptz,
  created_by       uuid references public.profiles(id) on delete set null,
  created_at       timestamptz not null default now(),
  updated_by       uuid references public.profiles(id) on delete set null,
  updated_at       timestamptz not null default now(),
  constraint event_guests_name_given check (btrim(name) <> ''),
  constraint event_guests_source check (source in ('ticket','free')),
  constraint event_guests_status check (status in ('registered','cancelled')),
  constraint event_guests_ticket_whole check (source = 'free' or (invoice_id is not null and invoice_item_id is not null))
);
create index if not exists event_guests_event_idx on public.event_guests(event_id);
create index if not exists event_guests_item_idx on public.event_guests(invoice_item_id) where invoice_item_id is not null;
create index if not exists event_guests_invoice_idx on public.event_guests(invoice_id) where invoice_id is not null;

create table if not exists public.event_guest_days (
  guest_id      uuid not null references public.event_guests(id) on delete cascade,
  day           date not null,
  attended_at   timestamptz,
  checked_in_by uuid references public.profiles(id) on delete set null,
  check_in_code text,
  primary key (guest_id, day)
);

-- Staff decisions on which event an invoice is a sale of. event_id null:
-- "not an event sale".
create table if not exists public.event_invoice_overrides (
  invoice_id uuid primary key references public.invoices(id) on delete cascade,
  event_id   uuid references public.events(id),
  reason     text,
  set_by     uuid references public.profiles(id) on delete set null,
  set_at     timestamptz not null default now()
);
create index if not exists event_invoice_overrides_event_idx on public.event_invoice_overrides(event_id);

-- Read and written only through the functions below.
alter table public.events enable row level security;
alter table public.event_days enable row level security;
alter table public.event_stores enable row level security;
alter table public.event_ticket_options enable row level security;
alter table public.event_guests enable row level security;
alter table public.event_guest_days enable row level security;
alter table public.event_invoice_overrides enable row level security;
revoke all on table public.events, public.event_days, public.event_stores, public.event_ticket_options,
  public.event_guests, public.event_guest_days, public.event_invoice_overrides from anon, authenticated;
grant all on table public.events, public.event_days, public.event_stores, public.event_ticket_options,
  public.event_guests, public.event_guest_days, public.event_invoice_overrides to service_role;

-- ── 2. The rules (internal) ────────────────────────────────────────────────

-- Anyone who works in a store: Owner, Admin, Manager or Staff, active.
create or replace function public.event_is_staff()
returns boolean language sql stable security definer set search_path to 'public' as $f$
  select exists (select 1 from public.profiles p
                  where p.id = auth.uid() and p.is_active and p.deleted_at is null
                    and p.role in ('owner','admin','manager','staff'))
$f$;

-- Who runs an event (guest list, check-in): staff with access to one of its
-- stores. Owners and Admins have access to every store.
create or replace function public.event_can_run(p_event_id uuid)
returns boolean language sql stable security definer set search_path to 'public' as $f$
  select public.event_is_staff()
     and exists (select 1 from public.event_stores es
                  where es.event_id = p_event_id and public.user_has_store_access(es.store_id))
$f$;

-- An option's price per person on a business date: the early-bird price on or
-- before the event's early-bird day, otherwise the full price.
create or replace function public.event_ticket_price(p_option_id uuid, p_business_date date)
returns numeric language sql stable security definer set search_path to 'public' as $f$
  select round(o.price * case when e.early_bird_until is not null and p_business_date <= e.early_bird_until
                              then (100 - e.early_bird_percent) / 100.0 else 1 end, 2)
    from public.event_ticket_options o join public.events e on e.id = o.event_id
   where o.id = p_option_id
$f$;

-- The date a ticket is priced on. The business date decides, but a backdated
-- invoice earns an early-bird price only when an Owner, Admin or Manager saves
-- it (the owner, 29 Sep 2026): for anyone else a ticket is priced on the later
-- of the business date and today in Singapore.
create or replace function public.event_ticket_price_date(p_business_date date)
returns date language sql stable security definer set search_path to 'public' as $f$
  select case when public.is_manager_or_above() then p_business_date
              else greatest(p_business_date, (now() at time zone 'Asia/Singapore')::date) end
$f$;

-- Checks one ticket line of an invoice payload and prices it. p_kept_option and
-- p_kept_quantity are the saved line's option and people: a line that keeps
-- its option may still be corrected after sales close or the event ends, but
-- may not gain people then. It takes a share lock on the event, so a change to
-- the event's days or options waits for the sale (and the other way round).
create or replace function public.event_ticket_line_check(p_line jsonb, p_business_date date,
  p_kept_option uuid default null, p_kept_quantity integer default null)
returns jsonb language plpgsql volatile security definer set search_path to 'public' as $f$
declare
  o public.event_ticket_options%rowtype; e public.events%rowtype;
  v_qty integer; v_days date[]; v_all date[]; v_given integer; v_kept boolean; v_closed text;
begin
  v_qty := (p_line->>'quantity')::integer;
  select * into o from public.event_ticket_options where id = nullif(p_line->>'event_ticket_option_id', '')::uuid;
  if not found then raise exception 'Choose which event ticket this line is'; end if;
  select * into e from public.events where id = o.event_id for share;
  if e.deleted_at is not null then raise exception 'The event "%" has been deleted', e.name; end if;
  select array_agg(d.day order by d.day) into v_all from public.event_days d where d.event_id = e.id;
  if v_all is null then raise exception 'The event "%" has no days', e.name; end if;
  v_kept := p_kept_option is not null and p_kept_option = o.id;
  v_closed := case
    when not e.is_active or not o.is_active then format('"%s" tickets for "%s" are not on sale', o.name, e.name)
    when p_business_date > v_all[cardinality(v_all)] then
      format('"%s" ended on %s, so its tickets cannot go on an invoice dated %s', e.name,
        to_char(v_all[cardinality(v_all)], 'DD Mon YYYY'), to_char(p_business_date, 'DD Mon YYYY')) end;
  if v_closed is not null and not v_kept then raise exception '%', v_closed; end if;
  if v_closed is not null and v_qty > coalesce(p_kept_quantity, 0) then
    raise exception '%. The ticket can be corrected, but no one can be added to it.', v_closed; end if;
  if nullif(p_line->>'line_voucher_id', '') is not null then
    raise exception 'A line voucher cannot discount an event ticket. Use a manual discount or an invoice discount voucher.'; end if;

  if jsonb_typeof(p_line->'event_days') = 'array' then
    v_days := array(select distinct (x #>> '{}')::date from jsonb_array_elements(p_line->'event_days') x order by 1);
  end if;
  if coalesce(cardinality(v_days), 0) = 0 then
    if o.days_count = cardinality(v_all) then v_days := v_all;
    else raise exception 'Choose % day(s) for the "%" ticket', o.days_count, o.name; end if;
  end if;
  if cardinality(v_days) <> o.days_count then
    raise exception 'The "%" ticket is for % day(s), but % were chosen', o.name, o.days_count, cardinality(v_days); end if;
  if not (v_days <@ v_all) then
    raise exception 'A chosen day is not a day of "%"', e.name; end if;

  v_given := public.event_ticket_people_given(p_line->'attendees', o.name, v_qty);
  return jsonb_build_object('option_id', o.id, 'event_id', e.id, 'days', to_jsonb(v_days),
    'price', public.event_ticket_price(o.id, public.event_ticket_price_date(p_business_date)), 'name', e.name || ' — ' || o.name);
end $f$;

-- Every person on a ticket line is named, once per person on the line.
create or replace function public.event_ticket_people_given(p_attendees jsonb, p_option_name text, p_quantity integer)
returns integer language plpgsql immutable as $f$
declare v_given integer;
begin
  v_given := case when jsonb_typeof(p_attendees) = 'array' then jsonb_array_length(p_attendees) else 0 end;
  if v_given <> p_quantity then
    raise exception 'Name every person on the "%" ticket: % name(s) given for % person(s)', p_option_name, v_given, p_quantity; end if;
  if exists (select 1 from jsonb_array_elements(p_attendees) x
              where jsonb_typeof(x) <> 'object' or coalesce(btrim(x->>'name'), '') = '') then
    raise exception 'Every person on an event ticket needs a name'; end if;
  return v_given;
end $f$;

-- How much of a line has been refunded since the invoice was last reopened.
create or replace function public.event_ticket_line_refunded(p_item_id uuid)
returns numeric language sql stable security definer set search_path to 'public' as $f$
  select coalesce(sum((l.value->>'amount')::numeric), 0)
    from public.invoice_items it
    join public.invoices i on i.id = it.invoice_id
    join public.invoice_refunds r on r.invoice_id = i.id and (i.reopened_at is null or r.created_at > i.reopened_at)
    cross join lateral jsonb_array_elements(coalesce(r.outcome->'lines', '[]')) l
   where it.id = p_item_id and l.value->>'invoice_item_id' = p_item_id::text
     and not coalesce((l.value->>'overpayment')::boolean, false)
$f$;

-- What a ticket line brought in: its share of the invoice after discounts,
-- less what has been refunded of it.
create or replace function public.event_ticket_line_money(p_item_id uuid)
returns numeric language sql stable security definer set search_path to 'public' as $f$
  select greatest(coalesce(public.invoice_discounted_line_value(p_item_id), 0) - public.event_ticket_line_refunded(p_item_id), 0)
$f$;

-- Whether a line's people are coming, from its invoice: cancelled, refunded
-- or deleted invoices and wholly refunded lines cancel them; undoing that
-- (a reopen) restores them. People taken off the line stay off.
create or replace function public.event_ticket_guests_follow_line(p_item_id uuid)
returns void language plpgsql security definer set search_path to 'public' as $f$
declare it public.invoice_items%rowtype; inv public.invoices%rowtype; v_reason text;
begin
  select * into it from public.invoice_items where id = p_item_id;
  if not found or it.line_kind <> 'event_ticket' then return; end if;
  select * into inv from public.invoices where id = it.invoice_id;
  v_reason := case
    when inv.deleted_at is not null or inv.status in ('cancelled','refunded') then 'Invoice cancelled or refunded'
    when public.event_ticket_line_refunded(p_item_id) > 0
         and public.event_ticket_line_refunded(p_item_id) >= coalesce(public.invoice_discounted_line_value(p_item_id), 0) - 0.005
      then 'Ticket refunded' end;
  if v_reason is not null then
    update public.event_guests
       set status = 'cancelled', cancelled_reason = v_reason, cancelled_at = now(), updated_at = now()
     where invoice_item_id = p_item_id
       and (status = 'registered' or cancelled_reason in ('Invoice cancelled or refunded', 'Ticket refunded'))
       and cancelled_reason is distinct from v_reason;
  else
    update public.event_guests
       set status = 'registered', cancelled_reason = null, cancelled_at = null, updated_at = now()
     where invoice_item_id = p_item_id and status = 'cancelled'
       and cancelled_reason in ('Invoice cancelled or refunded', 'Ticket refunded');
  end if;
end $f$;

-- Makes a ticket line's guests match the line: its people (when the payload
-- names them), its option and its days. A person keeps their guest record
-- (and check-ins) by guest_id. People taken off the line are cancelled. The
-- people on the line are those registered and those cancelled only because
-- their invoice or ticket was (who come back if that is undone).
create or replace function public.event_sync_ticket_line(p_item_id uuid, p_line jsonb)
returns void language plpgsql security definer set search_path to 'public' as $f$
declare
  it public.invoice_items%rowtype; o public.event_ticket_options%rowtype; inv public.invoices%rowtype;
  a jsonb; k integer := 0; v_gid uuid; v_keep uuid[] := '{}'; g record;
  v_before jsonb; v_after jsonb;
begin
  select * into it from public.invoice_items where id = p_item_id;
  if not found or it.line_kind <> 'event_ticket' then return; end if;
  select * into o from public.event_ticket_options where id = it.event_ticket_option_id;
  select * into inv from public.invoices where id = it.invoice_id;
  select coalesce(jsonb_agg(jsonb_build_object('guest_id', g2.id, 'name', g2.name, 'phone', g2.phone) order by g2.line_position, g2.id), '[]')
    into v_before from public.event_guests g2
   where g2.invoice_item_id = p_item_id
     and (g2.status = 'registered' or g2.cancelled_reason in ('Invoice cancelled or refunded', 'Ticket refunded'));

  if jsonb_typeof(p_line->'attendees') = 'array' then
    -- The line's people must still be one name per person, whatever else changed.
    perform public.event_ticket_people_given(p_line->'attendees', o.name, it.quantity);
    for a in select x from jsonb_array_elements(p_line->'attendees') x loop
      k := k + 1;
      v_gid := null;
      if nullif(a->>'guest_id', '') is not null then
        select g2.id into v_gid from public.event_guests g2
         where g2.id = (a->>'guest_id')::uuid and g2.invoice_item_id = p_item_id;
        if v_gid is null then
          raise exception 'A person on this ticket line belongs to another ticket. Reload the invoice and try again.'; end if;
        if v_gid = any(v_keep) then raise exception 'A person is listed twice on one ticket line'; end if;
        update public.event_guests
           set name = btrim(a->>'name'), phone = nullif(btrim(coalesce(a->>'phone', '')), ''),
               customer_id = nullif(a->>'customer_id', '')::uuid,
               event_id = o.event_id, ticket_option_id = o.id, line_position = k,
               status = 'registered', cancelled_reason = null, cancelled_at = null,
               updated_at = now(), updated_by = auth.uid()
         where id = v_gid;
      else
        insert into public.event_guests
          (event_id, name, phone, customer_id, source, invoice_id, invoice_item_id, ticket_option_id,
           line_position, registered_by, created_by, updated_by)
        values (o.event_id, btrim(a->>'name'), nullif(btrim(coalesce(a->>'phone', '')), ''),
                nullif(a->>'customer_id', '')::uuid, 'ticket', it.invoice_id, p_item_id, o.id,
                k, coalesce(inv.created_by, auth.uid()), auth.uid(), auth.uid())
        returning id into v_gid;
      end if;
      v_keep := v_keep || v_gid;
    end loop;
    update public.event_guests
       set status = 'cancelled', cancelled_reason = 'Taken off the ticket line', cancelled_at = now(),
           line_position = null, updated_at = now(), updated_by = auth.uid()
     where invoice_item_id = p_item_id and not (id = any(v_keep))
       and (status = 'registered' or cancelled_reason in ('Invoice cancelled or refunded', 'Ticket refunded'));
  else
    -- Unnamed in this payload (an unchanged line): the people follow the line's option.
    update public.event_guests set event_id = o.event_id, ticket_option_id = o.id
     where invoice_item_id = p_item_id
       and (status = 'registered' or cancelled_reason in ('Invoice cancelled or refunded', 'Ticket refunded'))
       and (event_id, ticket_option_id) is distinct from (o.event_id, o.id);
  end if;

  -- Every person on the line comes on the line's days.
  for g in select g3.id, g3.name from public.event_guests g3
            where g3.invoice_item_id = p_item_id
              and (g3.status = 'registered' or g3.cancelled_reason in ('Invoice cancelled or refunded', 'Ticket refunded')) loop
    if exists (select 1 from public.event_guest_days d
                where d.guest_id = g.id and d.attended_at is not null and not (d.day = any(it.event_days))) then
      raise exception '% has already checked in on a day this ticket no longer covers. Keep that day on the ticket.', g.name; end if;
    delete from public.event_guest_days d where d.guest_id = g.id and not (d.day = any(it.event_days));
    insert into public.event_guest_days (guest_id, day)
    select g.id, x from unnest(it.event_days) x
    on conflict (guest_id, day) do nothing;
  end loop;

  -- A cancelled, refunded or deleted invoice, or a refunded line, keeps its people off.
  perform public.event_ticket_guests_follow_line(p_item_id);

  select coalesce(jsonb_agg(jsonb_build_object('guest_id', g2.id, 'name', g2.name, 'phone', g2.phone) order by g2.line_position, g2.id), '[]')
    into v_after from public.event_guests g2
   where g2.invoice_item_id = p_item_id
     and (g2.status = 'registered' or g2.cancelled_reason in ('Invoice cancelled or refunded', 'Ticket refunded'));
  if v_after is distinct from v_before then
    perform public.write_audit_ex('invoices', it.invoice_id, 'event_ticket_people_changed',
      jsonb_build_object('invoice_item_id', p_item_id, 'people', v_before),
      jsonb_build_object('invoice_item_id', p_item_id, 'invoice_no', inv.invoice_no, 'people', v_after),
      'events', null, inv.store_id);
  end if;
end $f$;

-- The names on an invoice's unchanged ticket lines. correct_invoice treats an
-- invoice whose lines and header are unchanged as unchanged, and a person's
-- name is not part of what makes a line; so names are taken first. The lines
-- taken here are noted, so the invoice update that may follow does not take
-- them twice.
create or replace function public.event_sync_ticket_names(p_invoice_id uuid, p_items jsonb)
returns void language plpgsql security definer set search_path to 'public' as $f$
declare x jsonb; v_done text := '';
begin
  if jsonb_typeof(p_items) is distinct from 'array' then return; end if;
  for x in select v from jsonb_array_elements(p_items) v
            where v->>'kind' = 'event_ticket' and nullif(v->>'invoice_item_id', '') is not null loop
    if exists (select 1 from public.invoice_items ii where ii.id = (x->>'invoice_item_id')::uuid
                 and ii.invoice_id = p_invoice_id and ii.line_kind = 'event_ticket')
       and public.invoice_line_matches((x->>'invoice_item_id')::uuid, x) then
      perform public.event_sync_ticket_line((x->>'invoice_item_id')::uuid, x);
      v_done := v_done || (x->>'invoice_item_id') || ',';
    end if;
  end loop;
  perform set_config('events.names_taken', v_done, true);
end $f$;

-- A ticket line removed from its invoice cancels its people.
create or replace function public.trg_event_ticket_line_removed()
returns trigger language plpgsql security definer set search_path to 'public' as $f$
begin
  if old.line_kind = 'event_ticket' then
    update public.event_guests
       set status = 'cancelled', cancelled_reason = 'Ticket line removed from the invoice', cancelled_at = now(),
           line_position = null, updated_at = now()
     where invoice_item_id = old.id
       and (status = 'registered' or cancelled_reason in ('Invoice cancelled or refunded', 'Ticket refunded'));
  end if;
  return old;
end $f$;
drop trigger if exists event_ticket_line_removed on public.invoice_items;
create trigger event_ticket_line_removed after delete on public.invoice_items
  for each row execute function public.trg_event_ticket_line_removed();

-- An invoice cancelled, refunded, deleted or reopened, and a refund recorded,
-- decide again whether its ticket people are coming.
create or replace function public.trg_event_guests_follow_invoice()
returns trigger language plpgsql security definer set search_path to 'public' as $f$
declare v_item uuid;
begin
  if (new.status, new.deleted_at, new.reopened_at) is not distinct from (old.status, old.deleted_at, old.reopened_at) then
    return new; end if;
  for v_item in select ii.id from public.invoice_items ii
                 where ii.invoice_id = new.id and ii.line_kind = 'event_ticket' loop
    perform public.event_ticket_guests_follow_line(v_item);
  end loop;
  return new;
end $f$;
drop trigger if exists event_guests_follow_invoice on public.invoices;
create trigger event_guests_follow_invoice after update of status, deleted_at, reopened_at on public.invoices
  for each row execute function public.trg_event_guests_follow_invoice();

create or replace function public.trg_event_guests_follow_refund()
returns trigger language plpgsql security definer set search_path to 'public' as $f$
declare v_item uuid;
begin
  for v_item in select ii.id from public.invoice_items ii
                 where ii.invoice_id = new.invoice_id and ii.line_kind = 'event_ticket' loop
    perform public.event_ticket_guests_follow_line(v_item);
  end loop;
  return new;
end $f$;
drop trigger if exists event_guests_follow_refund on public.invoice_refunds;
create trigger event_guests_follow_refund after insert or update of outcome, amount on public.invoice_refunds
  for each row execute function public.trg_event_guests_follow_refund();

-- Which event each invoice is a sale of, and why: 'staff' (marked by hand,
-- which also covers "not an event sale"), 'event_day' (dated on a day of an
-- event at one of its stores), or 'ticket' (holds a ticket to it). Deleted
-- invoices and deleted events are no one's.
create or replace function public.event_invoice_membership(p_invoice_ids uuid[])
returns table(invoice_id uuid, event_id uuid, source text)
language sql stable security definer set search_path to 'public' as $f$
  with inv as (
    select i.id, i.store_id, i.business_date from public.invoices i
     where i.id = any(p_invoice_ids) and i.deleted_at is null),
  on_day as (
    select distinct on (inv.id) inv.id as invoice_id, e.id as event_id
      from inv
      join public.event_stores es on es.store_id = inv.store_id
      join public.event_days d on d.event_id = es.event_id and d.day = inv.business_date
      join public.events e on e.id = es.event_id and e.deleted_at is null
     order by inv.id, e.created_at, e.id),
  by_ticket as (
    select distinct on (ii.invoice_id) ii.invoice_id, e.id as event_id
      from public.invoice_items ii
      join public.event_ticket_options o on o.id = ii.event_ticket_option_id
      join public.events e on e.id = o.event_id and e.deleted_at is null
     where ii.invoice_id = any(p_invoice_ids) and ii.line_kind = 'event_ticket'
     order by ii.invoice_id, e.created_at, e.id),
  chosen as (
    select inv.id as invoice_id,
           case when ov.invoice_id is not null then ev.id else coalesce(d.event_id, t.event_id) end as event_id,
           case when ov.invoice_id is not null then 'staff'
                when d.event_id is not null then 'event_day' else 'ticket' end as source
      from inv
      left join public.event_invoice_overrides ov on ov.invoice_id = inv.id
      left join public.events ev on ev.id = ov.event_id and ev.deleted_at is null
      left join on_day d on d.invoice_id = inv.id
      left join by_ticket t on t.invoice_id = inv.id)
  select c.invoice_id, c.event_id, c.source from chosen c where c.event_id is not null
$f$;

-- The invoices an event's sales are drawn from, before membership decides.
create or replace function public.event_candidate_invoices(p_event_id uuid)
returns uuid[] language sql stable security definer set search_path to 'public' as $f$
  select coalesce(array_agg(distinct x.id), '{}') from (
    select i.id from public.invoices i
      join public.event_stores es on es.event_id = p_event_id and es.store_id = i.store_id
      join public.event_days d on d.event_id = p_event_id and d.day = i.business_date
     where i.deleted_at is null
    union
    select ii.invoice_id from public.invoice_items ii
      join public.event_ticket_options o on o.id = ii.event_ticket_option_id
     where o.event_id = p_event_id
    union
    select ov.invoice_id from public.event_invoice_overrides ov where ov.event_id = p_event_id) x
$f$;

-- People registered and checked in, per day of an event.
create or replace function public.event_day_load(p_event_id uuid)
returns table(day date, capacity integer, registered integer, attended integer)
language sql stable security definer set search_path to 'public' as $f$
  select d.day, d.capacity,
         (select count(*)::int from public.event_guest_days gd join public.event_guests g on g.id = gd.guest_id
           where g.event_id = d.event_id and g.status = 'registered' and gd.day = d.day),
         (select count(*)::int from public.event_guest_days gd join public.event_guests g on g.id = gd.guest_id
           where g.event_id = d.event_id and g.status = 'registered' and gd.day = d.day and gd.attended_at is not null)
    from public.event_days d where d.event_id = p_event_id order by d.day
$f$;

-- Everything the pages show about one event.
create or replace function public.event_summary(p_event_id uuid)
returns jsonb language sql stable security definer set search_path to 'public' as $f$
  select jsonb_build_object(
    'id', e.id, 'name', e.name, 'description', e.description,
    'daily_start', to_char(e.daily_start, 'HH24:MI'), 'daily_end', to_char(e.daily_end, 'HH24:MI'),
    'early_bird_until', e.early_bird_until, 'early_bird_percent', e.early_bird_percent,
    'is_active', e.is_active, 'notes', e.notes, 'created_at', e.created_at,
    'first_day', (select min(d.day) from public.event_days d where d.event_id = e.id),
    'last_day', (select max(d.day) from public.event_days d where d.event_id = e.id),
    'days', coalesce((select jsonb_agg(jsonb_build_object('day', l.day, 'capacity', l.capacity,
                        'registered', l.registered, 'attended', l.attended) order by l.day)
                      from public.event_day_load(e.id) l), '[]'),
    'stores', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name) order by s.name)
                        from public.event_stores es join public.stores s on s.id = es.store_id
                       where es.event_id = e.id), '[]'),
    'options', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'name', o.name, 'days_count', o.days_count,
                          'price', o.price, 'is_active', o.is_active, 'sort_order', o.sort_order,
                          'early_bird_price', case when e.early_bird_until is not null
                             then round(o.price * (100 - e.early_bird_percent) / 100.0, 2) end,
                          'sold', (select exists (select 1 from public.invoice_items ii where ii.event_ticket_option_id = o.id)))
                          order by o.sort_order, o.name)
                         from public.event_ticket_options o where o.event_id = e.id), '[]'),
    'guests', (select count(*) from public.event_guests g where g.event_id = e.id and g.status = 'registered'),
    'ticket_guests', (select count(*) from public.event_guests g where g.event_id = e.id and g.status = 'registered' and g.source = 'ticket'),
    'free_guests', (select count(*) from public.event_guests g where g.event_id = e.id and g.status = 'registered' and g.source = 'free'),
    'can_manage', public.is_manager_or_above(),
    'can_run', public.event_can_run(e.id))
  from public.events e where e.id = p_event_id
$f$;

-- ── 3. Invoices take ticket lines ──────────────────────────────────────────
create or replace function pg_temp.m370_patch(p_fn regprocedure, p_md5 text, p_from text[], p_to text[])
returns void language plpgsql as $p$
declare d text; n int; k int;
begin
  d := pg_get_functiondef(p_fn);
  if position('370:' in d) > 0 then raise notice '370: % already patched; left alone.', p_fn; return; end if;
  if md5(d) <> p_md5 then
    raise exception '370: % is not the version this was tested against (md5 %)', p_fn, md5(d); end if;
  for k in 1 .. cardinality(p_from) loop
    n := (length(d) - length(replace(d, p_from[k], ''))) / length(p_from[k]);
    if n <> 1 then raise exception '370: % anchor % found % times', p_fn, k, n; end if;
  end loop;
  for k in 1 .. cardinality(p_from) loop
    d := replace(d, p_from[k], p_to[k]);
  end loop;
  execute d;
end $p$;

-- The two invoice-writing functions share these anchors.
do $mig$
declare
  a_decl text := $a$  v_foc_rid uuid; v_foc_rtext text; v_foc_resolved text; v_foc_total numeric := 0;
begin
$a$;
  a_p1 text := $a$    elsif v_kind = 'credit_package' then
      if v_qty <> 1 then raise exception 'A credit package line must have quantity 1'; end if;
$a$;
  a_notin text := $a$    if v_kind not in ('promotion','voucher','therapy','special_product','rental','credit_package','premium_bundle') then
$a$;
  a_p2 text := $a$    elsif v_kind = 'credit_package' then
      v_product_id := (v_item->>'credit_package_id')::uuid;
$a$;
  r_notin text := $r$    -- 370: an event ticket is not a product either.
    if v_kind not in ('promotion','voucher','therapy','special_product','rental','credit_package','premium_bundle','event_ticket') then
$r$;
begin
  -- create_invoice (the 8-argument one the app calls).
  perform pg_temp.m370_patch('public.create_invoice(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb)',
    '328caeb484f032268d240409d67cf7bb',
    array[a_decl, a_p1, a_notin, a_p2],
    array[
$r$  v_foc_rid uuid; v_foc_rtext text; v_foc_resolved text; v_foc_total numeric := 0;
  v_ev jsonb; v_bdate date;
begin
  -- 370: an event ticket is priced on the invoice's business date, which
  -- create_invoice_with_details passes in (it sets the date after this runs).
  v_bdate := coalesce(nullif(current_setting('invoice.business_date', true), '')::date,
                      (now() at time zone 'Asia/Singapore')::date);
$r$,
$r$    elsif v_kind = 'event_ticket' then
      -- 370: the option, its day(s) and a name for every person; the price per
      -- person is the option's on the business date (early bird or full).
      v_ev := public.event_ticket_line_check(v_item, v_bdate, null);
      v_price := (v_ev->>'price')::numeric;
      v_gross := v_price * v_qty;

$r$ || a_p1,
      r_notin,
$r$    elsif v_kind = 'event_ticket' then
      -- 370: the ticket line, then its people on the guest list.
      v_ev := public.event_ticket_line_check(v_item, v_bdate, null);
      v_price := (v_ev->>'price')::numeric;
      v_gross := v_price * v_qty;
      v_foc_amt := case when v_foc_qty > 0 then round(v_gross * v_foc_qty::numeric / v_qty::numeric, 2) else 0 end;
      v_line_total := round(v_gross - v_foc_amt, 2);
      insert into public.invoice_items
        (invoice_id, line_kind, product_id, quantity, unit_price, line_total,
         price_source, price_source_id, store_id_snapshot, original_price,
         event_ticket_option_id, event_days, item_name_snapshot,
         foc_quantity, is_foc, foc_amount, foc_original_unit_price, foc_reason_id, foc_reason, foc_by, foc_at)
      values (v_invoice_id, 'event_ticket'::public.invoice_line_kind, null, v_qty, v_price, v_line_total,
              'event_ticket', (v_ev->>'option_id')::uuid, p_store_id, v_price,
              (v_ev->>'option_id')::uuid, array(select jsonb_array_elements_text(v_ev->'days'))::date[], v_ev->>'name',
              v_foc_qty, (v_foc_qty = v_qty and v_foc_qty > 0), v_foc_amt,
              case when v_foc_qty > 0 then v_price end, v_foc_rid, v_foc_resolved,
              case when v_foc_qty > 0 then auth.uid() end, case when v_foc_qty > 0 then now() end)
      returning id into v_item_id;
      perform public.event_sync_ticket_line(v_item_id, v_item);

$r$ || a_p2]);

  -- update_invoice_internal (every edit and correction).
  perform pg_temp.m370_patch('public.update_invoice_internal(uuid,uuid,uuid,jsonb,numeric,text,uuid,jsonb,text,boolean)',
    '17eac33feba5acd2cffb41f1b4758892',
    array[a_decl, a_p1, a_notin, a_p2,
          $a$    if public.invoice_line_matches(nullif(v_item->>'invoice_item_id','')::uuid,v_item) then continue; end if;
$a$],
    array[
$r$  v_foc_rid uuid; v_foc_rtext text; v_foc_resolved text; v_foc_total numeric := 0;
  v_ev jsonb; v_kept_opt uuid; v_kept_qty integer;  -- 370
begin
$r$,
$r$    elsif v_kind = 'event_ticket' then
      -- 370: priced on the invoice's business date. A line that keeps its
      -- option may be corrected after sales close or the event ends, and a
      -- saved line keeps the price it was sold at (its unit_price comes back).
      v_ev := public.event_ticket_line_check(v_item, v_old.business_date,
        v_original_line.event_ticket_option_id, v_original_line.quantity);
      v_price := (v_ev->>'price')::numeric;
      v_gross := v_price * v_qty;
      -- A saved price travels with its option: moving a line to another
      -- option at the old price is a price override.
      if v_item ? 'unit_price' and v_original_line.id is not null
         and v_original_line.event_ticket_option_id is distinct from (v_ev->>'option_id')::uuid
         and not public.is_owner_or_manager() then
        raise exception 'Only an Owner or Manager can override invoice prices'; end if;

$r$ || a_p1,
      r_notin,
$r$    elsif v_kind = 'event_ticket' then
      -- 370: the ticket line, then its people on the guest list.
      select x.event_ticket_option_id, x.quantity into v_kept_opt, v_kept_qty from public.invoice_items x
       where x.id = nullif(v_item->>'invoice_item_id','')::uuid and x.invoice_id = p_invoice_id;
      v_ev := public.event_ticket_line_check(v_item, v_old.business_date, v_kept_opt, v_kept_qty);
      v_price := coalesce((v_item->>'unit_price')::numeric, (v_ev->>'price')::numeric);
      v_gross := v_price * v_qty;
      v_foc_amt := case when v_foc_qty > 0 then round(v_gross * v_foc_qty::numeric / v_qty::numeric, 2) else 0 end;
      v_line_total := round(v_gross - v_foc_amt, 2);
      insert into public.invoice_items
        (id, invoice_id, line_kind, product_id, quantity, unit_price, line_total, line_voucher_id, line_discount,
         price_source, price_source_id, store_id_snapshot, original_price,
         event_ticket_option_id, event_days, item_name_snapshot,
         foc_quantity, is_foc, foc_amount, foc_original_unit_price, foc_reason_id, foc_reason, foc_by, foc_at)
      values (coalesce(nullif(v_item->>'invoice_item_id','')::uuid, gen_random_uuid()), p_invoice_id,
              'event_ticket'::public.invoice_line_kind, null, v_qty, v_price, v_line_total, null, 0,
              'event_ticket', (v_ev->>'option_id')::uuid, v_store_id, v_price,
              (v_ev->>'option_id')::uuid, array(select jsonb_array_elements_text(v_ev->'days'))::date[], v_ev->>'name',
              v_foc_qty, (v_foc_qty = v_qty and v_foc_qty > 0), v_foc_amt,
              case when v_foc_qty > 0 then v_price end, v_foc_rid, v_foc_resolved,
              case when v_foc_qty > 0 then auth.uid() end, case when v_foc_qty > 0 then now() end)
      -- The name it was sold under stays unless the option changes (the
      -- name-snapshot trigger decides).
      on conflict (id) do update set line_kind=excluded.line_kind, product_id=excluded.product_id,
        quantity=excluded.quantity, unit_price=excluded.unit_price, line_total=excluded.line_total,
        line_voucher_id=excluded.line_voucher_id, line_discount=excluded.line_discount,
        price_source=excluded.price_source, price_source_id=excluded.price_source_id,
        store_id_snapshot=excluded.store_id_snapshot, original_price=excluded.original_price,
        event_ticket_option_id=excluded.event_ticket_option_id, event_days=excluded.event_days,
        foc_quantity=excluded.foc_quantity, is_foc=excluded.is_foc, foc_amount=excluded.foc_amount,
        foc_original_unit_price=excluded.foc_original_unit_price, foc_reason_id=excluded.foc_reason_id,
        foc_reason=excluded.foc_reason, foc_by=excluded.foc_by, foc_at=excluded.foc_at
      returning id into v_item_id;
      perform public.event_sync_ticket_line(v_item_id, v_item);

$r$ || a_p2,
$r$    if public.invoice_line_matches(nullif(v_item->>'invoice_item_id','')::uuid,v_item) then
      -- 370: an unchanged ticket line still takes its people's names, unless
      -- correct_invoice has just taken them.
      if v_kind = 'event_ticket'
         and position((v_item->>'invoice_item_id') || ',' in coalesce(current_setting('events.names_taken', true), '')) = 0 then
        perform public.event_sync_ticket_line((v_item->>'invoice_item_id')::uuid, v_item);
      end if;
      continue;
    end if;
$r$]);

  -- correct_invoice takes the people's names on unchanged ticket lines first
  -- (it returns early when nothing that makes a line has changed).
  perform pg_temp.m370_patch('public.correct_invoice(uuid,jsonb,jsonb,text,uuid)',
    '44cccc9944780bd6c22b7a0d739de33b',
    array[$a$ same_lines:=public.invoice_all_lines_match(i.id,p_items);
$a$],
    array[$r$ -- 370: the names of people on unchanged ticket lines.
 perform public.event_sync_ticket_names(i.id,p_items);
 same_lines:=public.invoice_all_lines_match(i.id,p_items);
$r$]);

  -- create_invoice_with_details hands the business date to create_invoice.
  perform pg_temp.m370_patch('public.create_invoice_with_details(uuid,uuid,jsonb,jsonb)',
    'f4b56d2e2155afb7a35f6e0b7a8a1bc1',
    array[$a$ v_id:=public.create_invoice($a$,
          $a$ update public.invoices set business_date=(p_header->>'business_date')::date,$a$],
    array[$r$ -- 370: event tickets are priced on this date.
 perform set_config('invoice.business_date', coalesce(p_header->>'business_date', ''), true);
 v_id:=public.create_invoice($r$,
          $r$ perform set_config('invoice.business_date', '', true);
 update public.invoices set business_date=(p_header->>'business_date')::date,$r$]);

  -- A ticket line is identified by its option and days too.
  perform pg_temp.m370_patch('public.invoice_line_matches(uuid,jsonb)',
    '383fa385ecf7d63003b2480e22e41d21',
    array[$a$'premium_bundle_id','line_voucher_id']$a$, $a$  if i.line_kind='premium_bundle' then
$a$],
    array[$r$'premium_bundle_id','line_voucher_id','event_ticket_option_id']$r$, $r$  if i.line_kind='event_ticket' then  -- 370: the days it covers
    if coalesce(i.event_days, '{}'::date[]) is distinct from
       array(select distinct (x #>> '{}')::date
               from jsonb_array_elements(case when jsonb_typeof(p_line->'event_days') = 'array'
                                              then p_line->'event_days' else '[]'::jsonb end) x order by 1) then
      return false; end if;
  end if;
  if i.line_kind='premium_bundle' then
$r$]);
end $mig$;

-- ── 4. Names, credit and diagnostics know a ticket ─────────────────────────
do $mig$
begin
  perform pg_temp.m370_patch('public.invoice_item_catalogue_name(public.invoice_items)',
    'd751bc8fae4f3ebdda7930329a826123',
    array[$a$    when 'premium_bundle'  then coalesce(nullif(btrim(it.plan_name_snapshot), ''),
                                         (select pb.name from public.premium_bundles pb where pb.id = it.premium_bundle_id))
$a$],
    array[$r$    when 'premium_bundle'  then coalesce(nullif(btrim(it.plan_name_snapshot), ''),
                                         (select pb.name from public.premium_bundles pb where pb.id = it.premium_bundle_id))
    -- 370: an event ticket is named by its event and option.
    when 'event_ticket'    then (select e.name || ' — ' || o.name from public.event_ticket_options o
                                   join public.events e on e.id = o.event_id where o.id = it.event_ticket_option_id)
$r$]);

  perform pg_temp.m370_patch('public.trg_invoice_item_name_snapshot()',
    '1040480e874104ecc31120d772819c81',
    array['new.premium_bundle_id)', 'old.premium_bundle_id)'],
    array['new.premium_bundle_id, new.event_ticket_option_id)  -- 370: a ticket''s option', 'old.premium_bundle_id, old.event_ticket_option_id)']);

  perform pg_temp.m370_patch('public.diagnose_invoice_stock(text)',
    '3f5a9e1f79639c938b16343e0fa6a780',
    array[$a$      when l.lk in ('therapy','credit_package') then 'no stock expected'$a$],
    array[$r$      when l.lk in ('therapy','credit_package','event_ticket') then 'no stock expected'  -- 370: a ticket moves no stock$r$]);

  -- Credit: a ticket line's purpose is "event" (old credit restricted to
  -- purposes keeps honouring it) and its spending category is event_ticket.
  perform pg_temp.m370_patch('public.invoice_line_credit_purpose(text)',
    '211a8b42fbbab6723403d88db08dbe2d',
    array[$a$    when 'event' then 'event'
$a$],
    array[$r$    when 'event_ticket' then 'event'  -- 370: a ticket's purpose
    when 'event' then 'event'
$r$]);

  perform pg_temp.m370_patch('public.purchase_category(text,uuid,uuid,uuid)',
    'fcbb28bfcbeeac876823a1dc21d4c317',
    array[$a$    when 'promotion' then 'promotion'
$a$],
    array[$r$    when 'promotion' then 'promotion'
    when 'event' then 'event_ticket'         -- 370: a ticket's category
    when 'event_ticket' then 'event_ticket'
$r$]);

  perform pg_temp.m370_patch('public.credit_spendable_categories()',
    '2b54da63d227d5a3f122eac0de43b958',
    array[$a$'own_product','third_party_product','other_product','promotion']::text[]$a$],
    array[$r$'own_product','third_party_product','other_product','promotion',
              'event_ticket']::text[]  -- 370: event tickets$r$]);

  perform pg_temp.m370_patch('public.customer_credit_eligibility(uuid)',
    'ed713f3296bc4fca15be5c428e2cb1fa',
    array[$a$'money_voucher','therapy_session','unlimited_therapy','promotion']) c$a$],
    array[$r$'money_voucher','therapy_session','unlimited_therapy','promotion',
             'event_ticket']) c  -- 370: event tickets$r$]);

  -- Where a line's name falls back to "item", a ticket shows its own.
  perform pg_temp.m370_patch('public.customer_purchase_timeline(uuid)',
    '53812cdc0b0c1c75924952914e411b3a',
    array[$a$coalesce(p.name, ii.plan_name_snapshot, v.name, pr.name, 'item')$a$],
    array[$r$coalesce(p.name, ii.plan_name_snapshot, v.name, pr.name, ii.item_name_snapshot /* 370: */, 'item')$r$]);

  perform pg_temp.m370_patch('public.report_foc_lines(date,date,uuid)',
    'e74b562b094eb6700260700f1822ae25',
    array[$a$coalesce(p.name, pr.name, vo.name, ii.plan_name_snapshot, 'Item')$a$],
    array[$r$coalesce(p.name, pr.name, vo.name, ii.plan_name_snapshot, ii.item_name_snapshot /* 370: */, 'Item')$r$]);

  perform pg_temp.m370_patch('public.invoice_foc_details(uuid)',
    '395fc5016305951388b44dd25512b031',
    array[$a$coalesce(p.name, pr.name, vo.name, ii.plan_name_snapshot, 'Item')$a$],
    array[$r$coalesce(p.name, pr.name, vo.name, ii.plan_name_snapshot, ii.item_name_snapshot /* 370: */, 'Item')$r$]);
end $mig$;

-- ── 5. What the pages call ─────────────────────────────────────────────────

-- The events a person can see: Owners and Admins every one; others those at a
-- store they work in.
create or replace function public.events_list()
returns jsonb language sql stable security definer set search_path to 'public' as $f$
  select coalesce(jsonb_agg(public.event_summary(e.id)
                   order by (select min(d.day) from public.event_days d where d.event_id = e.id) desc nulls last, e.created_at desc), '[]')
    from public.events e
   where e.deleted_at is null and public.event_can_run(e.id)
$f$;

-- Creates or changes an event with its days, stores and ticket options.
--   {id?, name, description, daily_start, daily_end, early_bird_until,
--    early_bird_percent, is_active, notes, days: [{day, capacity}],
--    store_ids: [...], options: [{id?, name, days_count, price, is_active, sort_order}]}
create or replace function public.event_save(p_event jsonb)
returns uuid language plpgsql security definer set search_path to 'public' as $f$
declare
  v_id uuid := nullif(p_event->>'id', '')::uuid; v_old jsonb; e public.events%rowtype;
  v_days date[]; v_n_days integer; v_stores uuid[]; x jsonb; v_opt uuid; v_bad text; v_cnt integer;
  v_keep_opts uuid[] := '{}';
begin
  if not public.is_manager_or_above() then raise exception 'Only an Owner, Admin or Manager can set up events'; end if;
  if coalesce(btrim(p_event->>'name'), '') = '' then raise exception 'Give the event a name'; end if;
  if v_id is not null then
    select * into e from public.events where id = v_id for update;
    if not found or e.deleted_at is not null then raise exception 'Event not found'; end if;
    if not public.event_can_run(v_id) then raise exception 'You do not have access to this event'; end if;
    v_old := public.event_summary(v_id);
  end if;

  -- Days
  if jsonb_typeof(p_event->'days') is distinct from 'array' or jsonb_array_length(p_event->'days') = 0 then
    raise exception 'Give the event at least one day'; end if;
  v_days := array(select (d->>'day')::date from jsonb_array_elements(p_event->'days') d order by 1);
  if exists (select 1 from unnest(v_days) x2 where x2 is null) then raise exception 'Every event day needs a date'; end if;
  if cardinality(v_days) <> (select count(distinct x2) from unnest(v_days) x2) then raise exception 'A day is listed twice'; end if;
  if exists (select 1 from jsonb_array_elements(p_event->'days') d
              where nullif(d->>'capacity', '') is not null and (d->>'capacity')::integer <= 0) then
    raise exception 'A day''s capacity must be more than zero, or left empty for no limit'; end if;
  v_n_days := cardinality(v_days);

  -- Stores
  v_stores := array(select distinct (s #>> '{}')::uuid from jsonb_array_elements(coalesce(p_event->'store_ids', '[]')) s);
  if cardinality(v_stores) = 0 then raise exception 'Choose the store(s) the event is at'; end if;
  if exists (select 1 from unnest(v_stores) s where not exists (
               select 1 from public.stores st where st.id = s and st.deleted_at is null)) then
    raise exception 'A chosen store was not found'; end if;
  -- A store is added or removed only by someone who works there; the event's
  -- other stores stay as they are, shown to that person or not.
  if exists (select 1 from unnest(v_stores) s where not public.user_has_store_access(s)
               and not exists (select 1 from public.event_stores es where es.event_id = v_id and es.store_id = s)) then
    raise exception 'You can only hold events at stores you work in'; end if;
  v_stores := v_stores || array(select es.store_id from public.event_stores es
                                 where es.event_id = v_id and not public.user_has_store_access(es.store_id)
                                   and not (es.store_id = any(v_stores)));

  -- Options
  if jsonb_typeof(p_event->'options') is distinct from 'array' or jsonb_array_length(p_event->'options') = 0 then
    raise exception 'Give the event at least one ticket option'; end if;
  for x in select * from jsonb_array_elements(p_event->'options') loop
    if coalesce(btrim(x->>'name'), '') = '' then raise exception 'Every ticket option needs a name'; end if;
    if nullif(x->>'days_count', '') is null or (x->>'days_count')::integer < 1 or (x->>'days_count')::integer > v_n_days then
      raise exception 'The "%" ticket must cover between 1 and % day(s)', x->>'name', v_n_days; end if;
    if nullif(x->>'price', '') is null or (x->>'price')::numeric < 0 then
      raise exception 'The "%" ticket needs a price of zero or more', x->>'name'; end if;
  end loop;
  if (select count(distinct lower(btrim(x2->>'name'))) from jsonb_array_elements(p_event->'options') x2)
     <> jsonb_array_length(p_event->'options') then raise exception 'Two ticket options have the same name'; end if;

  -- Early bird: both or neither.
  if (nullif(p_event->>'early_bird_until', '') is null) <> (nullif(p_event->>'early_bird_percent', '') is null) then
    raise exception 'An early bird needs both its last day and its discount'; end if;
  if nullif(p_event->>'early_bird_percent', '') is not null
     and ((p_event->>'early_bird_percent')::numeric <= 0 or (p_event->>'early_bird_percent')::numeric > 100) then
    raise exception 'The early-bird discount must be more than 0%% and at most 100%%'; end if;

  if v_id is null then
    insert into public.events (name, description, daily_start, daily_end, early_bird_until, early_bird_percent,
                               is_active, notes, created_by, updated_by)
    values (btrim(p_event->>'name'), nullif(btrim(coalesce(p_event->>'description', '')), ''),
            nullif(p_event->>'daily_start', '')::time, nullif(p_event->>'daily_end', '')::time,
            nullif(p_event->>'early_bird_until', '')::date, nullif(p_event->>'early_bird_percent', '')::numeric,
            coalesce((p_event->>'is_active')::boolean, true), nullif(btrim(coalesce(p_event->>'notes', '')), ''),
            auth.uid(), auth.uid())
    returning id into v_id;
  else
    -- A day that people are coming on, or that a ticket covers, stays.
    select string_agg(to_char(d.day, 'DD Mon YYYY'), ', ' order by d.day) into v_bad
      from public.event_days d
     where d.event_id = v_id and not (d.day = any(v_days))
       and (exists (select 1 from public.event_guest_days gd join public.event_guests g on g.id = gd.guest_id
                     where g.event_id = v_id and g.status = 'registered' and gd.day = d.day)
            or exists (select 1 from public.invoice_items ii join public.event_ticket_options o on o.id = ii.event_ticket_option_id
                        where o.event_id = v_id and d.day = any(ii.event_days)));
    if v_bad is not null then
      raise exception 'People are registered for %, so that day cannot be removed. Cancel or move them first.', v_bad; end if;
    update public.events
       set name = btrim(p_event->>'name'), description = nullif(btrim(coalesce(p_event->>'description', '')), ''),
           daily_start = nullif(p_event->>'daily_start', '')::time, daily_end = nullif(p_event->>'daily_end', '')::time,
           early_bird_until = nullif(p_event->>'early_bird_until', '')::date,
           early_bird_percent = nullif(p_event->>'early_bird_percent', '')::numeric,
           is_active = coalesce((p_event->>'is_active')::boolean, is_active),
           notes = nullif(btrim(coalesce(p_event->>'notes', '')), ''),
           updated_by = auth.uid(), updated_at = now()
     where id = v_id;
  end if;

  delete from public.event_days d where d.event_id = v_id and not (d.day = any(v_days));
  insert into public.event_days (event_id, day, capacity)
  select v_id, (d->>'day')::date, nullif(d->>'capacity', '')::integer from jsonb_array_elements(p_event->'days') d
  on conflict (event_id, day) do update set capacity = excluded.capacity;

  delete from public.event_stores es where es.event_id = v_id and not (es.store_id = any(v_stores));
  insert into public.event_stores (event_id, store_id) select v_id, s from unnest(v_stores) s
  on conflict do nothing;

  for x in select * from jsonb_array_elements(p_event->'options') loop
    v_opt := nullif(x->>'id', '')::uuid;
    if v_opt is not null then
      if not exists (select 1 from public.event_ticket_options where id = v_opt and event_id = v_id) then
        raise exception 'Ticket option "%" belongs to another event', x->>'name'; end if;
      if exists (select 1 from public.invoice_items ii where ii.event_ticket_option_id = v_opt)
         and (select days_count from public.event_ticket_options where id = v_opt) <> (x->>'days_count')::integer then
        raise exception 'The "%" ticket has been sold, so the number of days it covers cannot change. Add a new option instead.', x->>'name'; end if;
      update public.event_ticket_options
         set name = btrim(x->>'name'), days_count = (x->>'days_count')::integer, price = (x->>'price')::numeric,
             is_active = coalesce((x->>'is_active')::boolean, true), sort_order = coalesce((x->>'sort_order')::integer, 0),
             updated_at = now()
       where id = v_opt;
    else
      insert into public.event_ticket_options (event_id, name, days_count, price, is_active, sort_order)
      values (v_id, btrim(x->>'name'), (x->>'days_count')::integer, (x->>'price')::numeric,
              coalesce((x->>'is_active')::boolean, true), coalesce((x->>'sort_order')::integer, 0))
      returning id into v_opt;
    end if;
    v_keep_opts := v_keep_opts || v_opt;
  end loop;
  select string_agg(o.name, ', ') into v_bad from public.event_ticket_options o
   where o.event_id = v_id and not (o.id = any(v_keep_opts))
     and exists (select 1 from public.invoice_items ii where ii.event_ticket_option_id = o.id);
  if v_bad is not null then
    raise exception '"%" has been sold, so it cannot be removed. Take it off sale instead.', v_bad; end if;
  delete from public.event_ticket_options o where o.event_id = v_id and not (o.id = any(v_keep_opts));

  perform public.write_audit_ex('events', v_id, case when v_old is null then 'event_created' else 'event_changed' end,
    v_old, public.event_summary(v_id), 'events', null, null);
  return v_id;
end $f$;

-- Deletes an event nobody has bought a ticket to.
create or replace function public.event_delete(p_event_id uuid, p_reason text)
returns void language plpgsql security definer set search_path to 'public' as $f$
declare e public.events%rowtype;
begin
  if not public.is_manager_or_above() then raise exception 'Only an Owner, Admin or Manager can delete events'; end if;
  select * into e from public.events where id = p_event_id for update;
  if not found or e.deleted_at is not null then raise exception 'Event not found'; end if;
  if not public.event_can_run(p_event_id) then raise exception 'You do not have access to this event'; end if;
  if coalesce(btrim(p_reason), '') = '' then raise exception 'Give a reason for deleting the event'; end if;
  if exists (select 1 from public.invoice_items ii join public.event_ticket_options o on o.id = ii.event_ticket_option_id
              join public.invoices i on i.id = ii.invoice_id
              where o.event_id = p_event_id and i.deleted_at is null) then
    raise exception 'Tickets to "%" are on invoices, so it cannot be deleted. Take it off sale instead.', e.name; end if;
  update public.events set deleted_at = now(), is_active = false, updated_by = auth.uid(), updated_at = now()
   where id = p_event_id;
  perform public.write_audit_ex('events', p_event_id, 'event_deleted', public.event_summary(p_event_id), null,
    'events', btrim(p_reason), null);
end $f$;

-- The ticket options an invoice at this store, on this business date, can
-- carry: of active events whose last day is on or after the date. Each comes
-- with its price on that date and the people already registered per day.
create or replace function public.event_ticket_options_for_sale(p_store_id uuid, p_business_date date)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $f$
begin
  if public.current_user_role() is null then raise exception 'No profile for current user'; end if;
  if not public.user_has_store_access(p_store_id) then raise exception 'You do not have access to this store'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'option_id', o.id, 'option_name', o.name, 'days_count', o.days_count, 'price', o.price,
             'unit_price', public.event_ticket_price(o.id, public.event_ticket_price_date(p_business_date)),
             'early_bird', e.early_bird_until is not null and public.event_ticket_price_date(p_business_date) <= e.early_bird_until,
             'early_bird_until', e.early_bird_until,
             'event_id', e.id, 'event_name', e.name,
             'days', (select jsonb_agg(jsonb_build_object('day', l.day, 'capacity', l.capacity, 'registered', l.registered)
                                       order by l.day) from public.event_day_load(e.id) l))
           order by (select min(d.day) from public.event_days d where d.event_id = e.id), e.name, o.sort_order, o.name)
      from public.event_ticket_options o join public.events e on e.id = o.event_id
     where o.is_active and e.is_active and e.deleted_at is null
       and (select max(d.day) from public.event_days d where d.event_id = e.id) >= p_business_date), '[]');
end $f$;

-- An invoice's ticket lines with their people, and which event it is a sale of.
create or replace function public.invoice_event_guests(p_invoice_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $f$
declare inv public.invoices%rowtype;
begin
  select * into inv from public.invoices where id = p_invoice_id;
  if not found then raise exception 'Invoice not found'; end if;
  if public.current_user_role() is null or not public.user_has_store_access(inv.store_id) then
    raise exception 'You do not have access to this invoice'; end if;
  return jsonb_build_object(
    'event', (select jsonb_build_object('event_id', m.event_id, 'event_name', e.name, 'source', m.source,
                                        'override', exists (select 1 from public.event_invoice_overrides ov where ov.invoice_id = p_invoice_id))
                from public.event_invoice_membership(array[p_invoice_id]) m join public.events e on e.id = m.event_id),
    'marked_not_event', exists (select 1 from public.event_invoice_overrides ov
                                 where ov.invoice_id = p_invoice_id and ov.event_id is null),
    'lines', coalesce((
      select jsonb_agg(jsonb_build_object(
               'invoice_item_id', ii.id, 'event_id', e.id, 'event_name', e.name,
               'option_id', o.id, 'option_name', o.name, 'days_count', o.days_count,
               'days', to_jsonb(ii.event_days),
               'event_days', (select jsonb_agg(d.day order by d.day) from public.event_days d where d.event_id = e.id),
               -- The people on the line, including those off only while the
               -- invoice is cancelled or the ticket refunded.
               'guests', coalesce((select jsonb_agg(jsonb_build_object('guest_id', g.id, 'name', g.name, 'phone', g.phone,
                                     'customer_id', g.customer_id, 'status', g.status) order by g.line_position, g.created_at)
                                   from public.event_guests g where g.invoice_item_id = ii.id
                                    and (g.status = 'registered' or g.cancelled_reason in ('Invoice cancelled or refunded', 'Ticket refunded'))), '[]'))
             order by ii.id)
        from public.invoice_items ii
        join public.event_ticket_options o on o.id = ii.event_ticket_option_id
        join public.events e on e.id = o.event_id
       where ii.invoice_id = p_invoice_id and ii.line_kind = 'event_ticket'), '[]'));
end $f$;

-- The event each of these invoices is a sale of (for the invoice list).
create or replace function public.invoice_events(p_invoice_ids uuid[])
returns table(invoice_id uuid, event_id uuid, event_name text, source text)
language sql stable security definer set search_path to 'public' as $f$
  select m.invoice_id, m.event_id, e.name, m.source
    from public.event_invoice_membership(p_invoice_ids) m
    join public.events e on e.id = m.event_id
    join public.invoices i on i.id = m.invoice_id
   where public.current_user_role() is not null and public.user_has_store_access(i.store_id)
$f$;

-- Marks an invoice as a sale of an event, or (p_event_id null) as no event
-- sale, whatever its date and store say.
create or replace function public.set_invoice_event(p_invoice_id uuid, p_event_id uuid, p_reason text default null)
returns void language plpgsql security definer set search_path to 'public' as $f$
declare inv public.invoices%rowtype; v_old jsonb;
begin
  if not public.event_is_staff() then raise exception 'Only store staff can change an invoice''s event'; end if;
  select * into inv from public.invoices where id = p_invoice_id for update;
  if not found or inv.deleted_at is not null then raise exception 'Invoice not found'; end if;
  if not public.user_has_store_access(inv.store_id) then raise exception 'You do not have access to this invoice'; end if;
  if p_event_id is not null and not exists (select 1 from public.events where id = p_event_id and deleted_at is null) then
    raise exception 'Event not found'; end if;
  select to_jsonb(ov) into v_old from public.event_invoice_overrides ov where ov.invoice_id = p_invoice_id;
  insert into public.event_invoice_overrides (invoice_id, event_id, reason, set_by, set_at)
  values (p_invoice_id, p_event_id, nullif(btrim(coalesce(p_reason, '')), ''), auth.uid(), now())
  on conflict (invoice_id) do update set event_id = excluded.event_id, reason = excluded.reason,
    set_by = excluded.set_by, set_at = excluded.set_at;
  perform public.write_audit_ex('invoices', p_invoice_id, 'invoice_event_set', v_old,
    jsonb_build_object('invoice_no', inv.invoice_no, 'event_id', p_event_id,
                       'event_name', (select name from public.events where id = p_event_id)),
    'events', nullif(btrim(coalesce(p_reason, '')), ''), inv.store_id);
end $f$;

-- Undoes set_invoice_event: the invoice's date, store and tickets decide again.
create or replace function public.clear_invoice_event(p_invoice_id uuid)
returns void language plpgsql security definer set search_path to 'public' as $f$
declare inv public.invoices%rowtype; v_old jsonb;
begin
  if not public.event_is_staff() then raise exception 'Only store staff can change an invoice''s event'; end if;
  select * into inv from public.invoices where id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found'; end if;
  if not public.user_has_store_access(inv.store_id) then raise exception 'You do not have access to this invoice'; end if;
  delete from public.event_invoice_overrides ov where ov.invoice_id = p_invoice_id returning to_jsonb(ov) into v_old;
  if v_old is not null then
    perform public.write_audit_ex('invoices', p_invoice_id, 'invoice_event_cleared', v_old,
      jsonb_build_object('invoice_no', inv.invoice_no), 'events', null, inv.store_id);
  end if;
end $f$;

-- An event's guest list, with each person's days and check-ins.
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
     where g.event_id = p_event_id), '[]');
end $f$;

-- Adds or changes a guest. A free guest's days are chosen here; a ticket
-- guest's come from the invoice line, so only their name, phone, customer,
-- notes and the staff who registered them change here.
--   {id?, event_id, name, phone, customer_id, days: [...], registered_by, notes}
-- Returns the guest's id and any of their days now over capacity (a warning).
create or replace function public.event_save_guest(p_guest jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare
  v_id uuid := nullif(p_guest->>'id', '')::uuid; g public.event_guests%rowtype; v_event uuid;
  v_days date[]; v_by uuid; v_old jsonb;
begin
  if v_id is not null then
    select * into g from public.event_guests where id = v_id for update;
    if not found then raise exception 'Guest not found'; end if;
    v_event := g.event_id;
  else
    v_event := nullif(p_guest->>'event_id', '')::uuid;
  end if;
  if v_event is null or not exists (select 1 from public.events where id = v_event and deleted_at is null) then
    raise exception 'Event not found'; end if;
  if not public.event_can_run(v_event) then raise exception 'You do not have access to this event'; end if;
  if coalesce(btrim(p_guest->>'name'), '') = '' then raise exception 'Give the guest''s name'; end if;
  v_by := nullif(p_guest->>'registered_by', '')::uuid;
  if v_by is not null and not exists (select 1 from public.profiles p where p.id = v_by and p.is_active
                                         and p.deleted_at is null and p.role in ('owner','admin','manager','staff')) then
    raise exception 'The staff member who registered the guest was not found'; end if;
  if nullif(p_guest->>'customer_id', '') is not null
     and not exists (select 1 from public.customers where id = (p_guest->>'customer_id')::uuid and deleted_at is null) then
    raise exception 'Customer not found'; end if;

  if v_id is null or g.source = 'free' then
    v_days := array(select distinct (x #>> '{}')::date from jsonb_array_elements(coalesce(p_guest->'days', '[]')) x order by 1);
    if cardinality(v_days) = 0 then raise exception 'Choose the day(s) the guest is coming'; end if;
    if exists (select 1 from unnest(v_days) x where not exists (
                 select 1 from public.event_days d where d.event_id = v_event and d.day = x)) then
      raise exception 'A chosen day is not a day of this event'; end if;
  elsif p_guest ? 'days' and array(select distinct (x #>> '{}')::date from jsonb_array_elements(coalesce(p_guest->'days', '[]')) x order by 1)
        is distinct from array(select gd.day from public.event_guest_days gd where gd.guest_id = v_id order by 1) then
    raise exception 'A ticket guest''s days come from their invoice. Correct the invoice to change them.';
  end if;

  if v_id is null then
    insert into public.event_guests (event_id, name, phone, customer_id, source, registered_by, notes, created_by, updated_by)
    values (v_event, btrim(p_guest->>'name'), nullif(btrim(coalesce(p_guest->>'phone', '')), ''),
            nullif(p_guest->>'customer_id', '')::uuid, 'free', coalesce(v_by, auth.uid()),
            nullif(btrim(coalesce(p_guest->>'notes', '')), ''), auth.uid(), auth.uid())
    returning id into v_id;
    insert into public.event_guest_days (guest_id, day) select v_id, x from unnest(v_days) x;
    perform public.write_audit_ex('event_guests', v_id, 'event_guest_added', null,
      jsonb_build_object('event_id', v_event, 'days', to_jsonb(v_days)), 'events', null, null);
  else
    v_old := jsonb_build_object('name', g.name, 'phone', g.phone, 'customer_id', g.customer_id,
                                'registered_by', g.registered_by, 'notes', g.notes);
    update public.event_guests
       set name = btrim(p_guest->>'name'), phone = nullif(btrim(coalesce(p_guest->>'phone', '')), ''),
           customer_id = nullif(p_guest->>'customer_id', '')::uuid,
           registered_by = coalesce(v_by, registered_by), notes = nullif(btrim(coalesce(p_guest->>'notes', '')), ''),
           updated_at = now(), updated_by = auth.uid()
     where id = v_id;
    perform public.write_audit_ex('event_guests', v_id, 'event_guest_changed', v_old,
      (select jsonb_build_object('name', g2.name, 'phone', g2.phone, 'customer_id', g2.customer_id,
                                 'registered_by', g2.registered_by, 'notes', g2.notes)
         from public.event_guests g2 where g2.id = v_id), 'events', null, null);
    if g.source = 'free' then
      if exists (select 1 from public.event_guest_days gd where gd.guest_id = v_id and gd.attended_at is not null
                  and not (gd.day = any(v_days))) then
        raise exception '% has already checked in on a day being removed. Keep that day.', g.name; end if;
      delete from public.event_guest_days gd where gd.guest_id = v_id and not (gd.day = any(v_days));
      insert into public.event_guest_days (guest_id, day) select v_id, x from unnest(v_days) x
      on conflict (guest_id, day) do nothing;
    end if;
  end if;

  return jsonb_build_object('guest_id', v_id,
    'over_capacity', coalesce((select jsonb_agg(jsonb_build_object('day', l.day, 'capacity', l.capacity, 'registered', l.registered) order by l.day)
                                 from public.event_day_load(v_event) l
                                where l.capacity is not null and l.registered > l.capacity
                                  and l.day in (select gd.day from public.event_guest_days gd where gd.guest_id = v_id)), '[]'));
end $f$;

-- Cancels a free guest (ticket guests follow their invoice), or restores one.
create or replace function public.event_set_guest_cancelled(p_guest_id uuid, p_cancelled boolean, p_reason text default null)
returns void language plpgsql security definer set search_path to 'public' as $f$
declare g public.event_guests%rowtype;
begin
  select * into g from public.event_guests where id = p_guest_id for update;
  if not found then raise exception 'Guest not found'; end if;
  if not public.event_can_run(g.event_id) then raise exception 'You do not have access to this event'; end if;
  if g.source <> 'free' then
    raise exception 'A ticket guest comes from an invoice. Cancel or correct the invoice to remove them.'; end if;
  if p_cancelled then
    update public.event_guests set status = 'cancelled', cancelled_reason = nullif(btrim(coalesce(p_reason, '')), ''),
           cancelled_at = now(), updated_at = now(), updated_by = auth.uid()
     where id = p_guest_id and status = 'registered';
  else
    update public.event_guests set status = 'registered', cancelled_reason = null, cancelled_at = null,
           updated_at = now(), updated_by = auth.uid()
     where id = p_guest_id and status = 'cancelled';
  end if;
  perform public.write_audit_ex('event_guests', p_guest_id,
    case when p_cancelled then 'event_guest_cancelled' else 'event_guest_restored' end,
    jsonb_build_object('status', g.status), jsonb_build_object('event_id', g.event_id),
    'events', nullif(btrim(coalesce(p_reason, '')), ''), null);
end $f$;

-- Checks a guest in (or out) for a day, with an optional code for the day.
create or replace function public.event_check_in(p_guest_id uuid, p_day date, p_attended boolean, p_code text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare g public.event_guests%rowtype; r public.event_guest_days%rowtype;
begin
  select * into g from public.event_guests where id = p_guest_id;
  if not found then raise exception 'Guest not found'; end if;
  if not public.event_can_run(g.event_id) then raise exception 'You do not have access to this event'; end if;
  if g.status <> 'registered' then raise exception '% is not registered (cancelled)', g.name; end if;
  select * into r from public.event_guest_days where guest_id = p_guest_id and day = p_day for update;
  if not found then raise exception '% is not registered for %', g.name, to_char(p_day, 'DD Mon YYYY'); end if;
  if p_attended then
    update public.event_guest_days
       set attended_at = coalesce(attended_at, now()), checked_in_by = coalesce(checked_in_by, auth.uid()),
           check_in_code = nullif(btrim(coalesce(p_code, '')), '')
     where guest_id = p_guest_id and day = p_day returning * into r;
  else
    update public.event_guest_days set attended_at = null, checked_in_by = null, check_in_code = null
     where guest_id = p_guest_id and day = p_day returning * into r;
  end if;
  return jsonb_build_object('guest_id', r.guest_id, 'day', r.day, 'attended_at', r.attended_at,
                            'check_in_code', r.check_in_code);
end $f$;

-- The invoices that are an event's sales, at the stores the person can see.
create or replace function public.event_invoices(p_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $f$
begin
  if not public.event_can_run(p_event_id) then raise exception 'You do not have access to this event'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'invoice_id', i.id, 'invoice_no', i.invoice_no, 'business_date', i.business_date,
             'store_id', i.store_id, 'store_name', s.name, 'customer_id', i.customer_id, 'customer_name', c.full_name,
             'status', i.status, 'total_amount', i.total_amount, 'paid_amount', i.paid_amount, 'source', m.source,
             'ticket_people', (select coalesce(sum(ii.quantity), 0) from public.invoice_items ii
                                 join public.event_ticket_options o on o.id = ii.event_ticket_option_id
                                where ii.invoice_id = i.id and o.event_id = p_event_id),
             'ticket_total', (select coalesce(sum(public.event_ticket_line_money(ii.id)), 0) from public.invoice_items ii
                                join public.event_ticket_options o on o.id = ii.event_ticket_option_id
                               where ii.invoice_id = i.id and o.event_id = p_event_id))
           order by i.business_date desc, i.invoice_no desc)
      from public.event_invoice_membership(public.event_candidate_invoices(p_event_id)) m
      join public.invoices i on i.id = m.invoice_id
      join public.stores s on s.id = i.store_id
      left join public.customers c on c.id = i.customer_id
     where m.event_id = p_event_id and public.user_has_store_access(i.store_id)), '[]');
end $f$;

-- Reports: one row per event with a day in the period (every event when the
-- period is open): days, tickets by option (early bird and full price, and
-- their money after discounts and refunds), and event sales by store.
-- Cancelled, refunded and deleted invoices are left out.
create or replace function public.report_events(p_from date default null, p_to date default null)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $f$
begin
  if not public.is_manager_or_above() then raise exception 'Only an Owner, Admin or Manager can see event reports'; end if;
  return coalesce((
    select jsonb_agg(r order by r->>'first_day' desc nulls last)
      from (
        select jsonb_build_object(
          'event_id', e.id, 'name', e.name, 'is_active', e.is_active,
          'first_day', (select min(d.day) from public.event_days d where d.event_id = e.id),
          'last_day', (select max(d.day) from public.event_days d where d.event_id = e.id),
          'early_bird_until', e.early_bird_until,
          'days', coalesce((select jsonb_agg(jsonb_build_object('day', l.day, 'capacity', l.capacity,
                              'registered', l.registered, 'attended', l.attended,
                              'ticket', (select count(*) from public.event_guest_days gd join public.event_guests g on g.id = gd.guest_id
                                          where g.event_id = e.id and g.status = 'registered' and g.source = 'ticket' and gd.day = l.day),
                              'free', (select count(*) from public.event_guest_days gd join public.event_guests g on g.id = gd.guest_id
                                        where g.event_id = e.id and g.status = 'registered' and g.source = 'free' and gd.day = l.day))
                              order by l.day) from public.event_day_load(e.id) l), '[]'),
          'options', coalesce((select jsonb_agg(jsonb_build_object(
                                 'option_id', x.id, 'name', x.name, 'days_count', x.days_count, 'price', x.price,
                                 'people', x.people, 'early_bird_people', x.early_bird_people,
                                 'foc_people', x.foc_people, 'revenue', x.revenue) order by x.sort_order, x.name)
                               from (select o.id, o.name, o.days_count, o.price, o.sort_order,
                                            coalesce(sum(ii.quantity), 0) as people,
                                            coalesce(sum(ii.quantity) filter (where e.early_bird_until is not null
                                                                                and i.business_date <= e.early_bird_until), 0) as early_bird_people,
                                            coalesce(sum(ii.foc_quantity), 0) as foc_people,
                                            coalesce(sum(public.event_ticket_line_money(ii.id)), 0) as revenue
                                       from public.event_ticket_options o
                                       left join (public.invoice_items ii join public.invoices i
                                                    on i.id = ii.invoice_id and i.deleted_at is null
                                                   and i.status not in ('cancelled','refunded')
                                                   and public.user_has_store_access(i.store_id))
                                         on ii.event_ticket_option_id = o.id
                                      where o.event_id = e.id
                                      group by o.id, o.name, o.days_count, o.price, o.sort_order) x), '[]'),
          'sales', coalesce((select jsonb_agg(jsonb_build_object('store_id', x.store_id, 'store_name', x.store_name,
                               'invoices', x.n, 'total_amount', x.total, 'paid_amount', x.paid) order by x.store_name)
                             from (select i.store_id, s.name as store_name, count(*) as n,
                                          sum(i.total_amount) as total, sum(i.paid_amount) as paid
                                     from public.event_invoice_membership(public.event_candidate_invoices(e.id)) m
                                     join public.invoices i on i.id = m.invoice_id
                                     join public.stores s on s.id = i.store_id
                                    where m.event_id = e.id and i.status not in ('cancelled','refunded')
                                      and public.user_has_store_access(i.store_id)
                                    group by i.store_id, s.name) x), '[]')) as r
          from public.events e
         where e.deleted_at is null and public.event_can_run(e.id)
           and exists (select 1 from public.event_days d where d.event_id = e.id
                        and d.day between coalesce(p_from, '-infinity'::date) and coalesce(p_to, 'infinity'::date))
      ) q), '[]');
end $f$;

-- ── 6. Who may call what ───────────────────────────────────────────────────
-- Internal: reached only from inside the functions above and the invoice
-- functions, which run as the owner.
revoke all on function public.event_is_staff() from public, anon, authenticated;
revoke all on function public.event_can_run(uuid) from public, anon, authenticated;
revoke all on function public.event_ticket_price(uuid,date) from public, anon, authenticated;
revoke all on function public.event_ticket_price_date(date) from public, anon, authenticated;
revoke all on function public.event_ticket_line_check(jsonb,date,uuid,integer) from public, anon, authenticated;
revoke all on function public.event_ticket_people_given(jsonb,text,integer) from public, anon, authenticated;
revoke all on function public.event_ticket_line_refunded(uuid) from public, anon, authenticated;
revoke all on function public.event_ticket_line_money(uuid) from public, anon, authenticated;
revoke all on function public.event_ticket_guests_follow_line(uuid) from public, anon, authenticated;
revoke all on function public.trg_event_guests_follow_refund() from public, anon, authenticated;
revoke all on function public.event_sync_ticket_line(uuid,jsonb) from public, anon, authenticated;
revoke all on function public.event_sync_ticket_names(uuid,jsonb) from public, anon, authenticated;
revoke all on function public.trg_event_ticket_line_removed() from public, anon, authenticated;
revoke all on function public.trg_event_guests_follow_invoice() from public, anon, authenticated;
revoke all on function public.event_invoice_membership(uuid[]) from public, anon, authenticated;
revoke all on function public.event_candidate_invoices(uuid) from public, anon, authenticated;
revoke all on function public.event_day_load(uuid) from public, anon, authenticated;
revoke all on function public.event_summary(uuid) from public, anon, authenticated;
grant execute on function public.event_is_staff(), public.event_can_run(uuid), public.event_ticket_price(uuid,date),
  public.event_ticket_price_date(date),
  public.event_ticket_line_check(jsonb,date,uuid,integer), public.event_sync_ticket_line(uuid,jsonb),
  public.event_ticket_people_given(jsonb,text,integer), public.event_ticket_line_refunded(uuid),
  public.event_ticket_line_money(uuid), public.event_ticket_guests_follow_line(uuid),
  public.trg_event_guests_follow_refund(),
  public.event_sync_ticket_names(uuid,jsonb),
  public.trg_event_ticket_line_removed(), public.trg_event_guests_follow_invoice(),
  public.event_invoice_membership(uuid[]), public.event_candidate_invoices(uuid),
  public.event_day_load(uuid), public.event_summary(uuid) to service_role;

-- What the pages call; each checks who is asking.
revoke all on function public.events_list() from public, anon;
revoke all on function public.event_save(jsonb) from public, anon;
revoke all on function public.event_delete(uuid,text) from public, anon;
revoke all on function public.event_ticket_options_for_sale(uuid,date) from public, anon;
revoke all on function public.invoice_event_guests(uuid) from public, anon;
revoke all on function public.invoice_events(uuid[]) from public, anon;
revoke all on function public.set_invoice_event(uuid,uuid,text) from public, anon;
revoke all on function public.clear_invoice_event(uuid) from public, anon;
revoke all on function public.event_guest_list(uuid) from public, anon;
revoke all on function public.event_save_guest(jsonb) from public, anon;
revoke all on function public.event_set_guest_cancelled(uuid,boolean,text) from public, anon;
revoke all on function public.event_check_in(uuid,date,boolean,text) from public, anon;
revoke all on function public.event_invoices(uuid) from public, anon;
revoke all on function public.report_events(date,date) from public, anon;
grant execute on function public.events_list(), public.event_save(jsonb), public.event_delete(uuid,text),
  public.event_ticket_options_for_sale(uuid,date), public.invoice_event_guests(uuid), public.invoice_events(uuid[]),
  public.set_invoice_event(uuid,uuid,text), public.clear_invoice_event(uuid), public.event_guest_list(uuid),
  public.event_save_guest(jsonb), public.event_set_guest_cancelled(uuid,boolean,text),
  public.event_check_in(uuid,date,boolean,text), public.event_invoices(uuid), public.report_events(date,date)
  to authenticated, service_role;

notify pgrst, 'reload schema';
