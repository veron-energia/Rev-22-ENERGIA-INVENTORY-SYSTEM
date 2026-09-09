-- =====================================================================
-- ENERGIA — THERAPY SERVICE CATALOGUE
--
-- Individual therapy services, separate from unlimited-therapy packages. A
-- service is a thing that can be sold once, given by a voucher, or covered by
-- an unlimited entitlement — the catalogue says what it is and how often, not
-- who has it.
--
-- Pricing follows the pattern the rest of the catalogue already uses: one
-- standard price on the service, and an explicit per-store override where a
-- store differs. "Standard price" is the normal customer selling price. There
-- is no internal delivery cost here and none is implied.
--
-- Frequency rules are STRUCTURED, not free text, because something has to be
-- able to evaluate them. They are mirrored by src/lib/therapy/frequency.mjs and
-- a database test asserts the two agree.
--
-- What this deliberately does not do: it creates no appointment, records no
-- visit, and claims no live frequency enforcement. therapy_service_frequency_ok()
-- takes the session history as an argument precisely because there is no
-- authoritative session history yet — see section 5.
--
-- Additive. Seeds no services: the two examples belong in fixtures and a
-- reviewed setup step, not in a migration. Run independently of the invoice
-- (170-184) and other 2xx work.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. The services.
-- ---------------------------------------------------------------------
create table if not exists public.therapy_services (
  id uuid primary key default gen_random_uuid(),
  service_code text not null,
  name text not null,
  description text,

  -- The normal customer selling price, in SGD. Not a cost.
  standard_price numeric(12,2) not null check (standard_price >= 0),
  duration_minutes integer check (duration_minutes is null or (duration_minutes > 0 and duration_minutes <= 1440)),

  -- Structured, and readable beside it. The text is generated for display and
  -- is never what gets enforced.
  frequency_kind text not null default 'unrestricted'
    check (frequency_kind in ('per_day','per_week','per_month','per_hours','unrestricted')),
  frequency_max_per_period integer not null default 1 check (frequency_max_per_period between 1 and 100),
  frequency_interval_hours numeric(8,2) check (frequency_interval_hours is null or frequency_interval_hours > 0),

  is_active boolean not null default false,
  notes text,
  created_by uuid references public.profiles(id),
  updated_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,

  -- An hourly rule without an interval is not a rule.
  constraint therapy_service_hours_present
    check (frequency_kind <> 'per_hours' or frequency_interval_hours is not null),

  -- A service cannot be made active until it can actually be booked: duration
  -- and a chosen frequency are what a future calendar needs. Deactivated and
  -- draft services may be incomplete.
  constraint therapy_service_active_is_complete
    check (not is_active or (duration_minutes is not null and frequency_kind is not null))
);

create unique index if not exists uq_therapy_service_code
  on public.therapy_services (lower(service_code)) where deleted_at is null;

-- Where a service is offered. No row for a store means not offered there.
create table if not exists public.therapy_service_stores (
  service_id uuid not null references public.therapy_services(id) on delete cascade,
  store_id uuid not null references public.stores(id) on delete cascade,
  -- Null means "use the standard price". An override is an explicit decision.
  price_override numeric(12,2) check (price_override is null or price_override >= 0),
  is_available boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (service_id, store_id)
);

create index if not exists idx_therapy_service_store on public.therapy_service_stores (store_id);

-- ---------------------------------------------------------------------
-- 2. The price a given store actually charges.
-- ---------------------------------------------------------------------
create or replace function public.therapy_service_price(p_service_id uuid, p_store_id uuid default null)
returns numeric language sql stable set search_path = public as $function$
  select coalesce(
    (select ss.price_override from public.therapy_service_stores ss
      where ss.service_id = p_service_id and ss.store_id = p_store_id),
    (select s.standard_price from public.therapy_services s where s.id = p_service_id))
$function$;

create or replace function public.therapy_service_available_at(p_service_id uuid, p_store_id uuid)
returns boolean language sql stable set search_path = public as $function$
  select exists (
    select 1 from public.therapy_services s
      join public.therapy_service_stores ss on ss.service_id = s.id
     where s.id = p_service_id and ss.store_id = p_store_id
       and s.is_active and s.deleted_at is null and ss.is_available)
$function$;

-- ---------------------------------------------------------------------
-- 3. The frequency rule, as text and as a decision.
-- ---------------------------------------------------------------------
create or replace function public.therapy_frequency_description(
  p_kind text, p_max integer, p_hours numeric)
returns text language sql immutable as $function$
  select case p_kind
    when 'unrestricted' then 'No frequency limit.'
    when 'per_day'   then format('At most %s per calendar day (Singapore, midnight to midnight).',
                                 case when coalesce(p_max,1) = 1 then 'once' else coalesce(p_max,1) || ' times' end)
    when 'per_week'  then format('At most %s per calendar week (Singapore, Monday to Sunday).',
                                 case when coalesce(p_max,1) = 1 then 'once' else coalesce(p_max,1) || ' times' end)
    when 'per_month' then format('At most %s per calendar month (Singapore, 1st to the last date).',
                                 case when coalesce(p_max,1) = 1 then 'once' else coalesce(p_max,1) || ' times' end)
    when 'per_hours' then format('At most %s every %s hour%s, measured from the start of the previous session.',
                                 case when coalesce(p_max,1) = 1 then 'once' else coalesce(p_max,1) || ' times' end,
                                 trim(trailing '.' from trim(trailing '0' from p_hours::text)),
                                 case when p_hours = 1 then '' else 's' end)
    else 'Frequency rule not recognised.' end
$function$;

-- The Singapore period a moment belongs to. Singapore is a fixed +08:00 with no
-- daylight saving, so these boundaries never move.
create or replace function public.sgt_period_key(p_at timestamptz, p_kind text)
returns text language sql immutable as $function$
  select case p_kind
    when 'per_day'  then to_char(p_at at time zone 'Asia/Singapore', 'YYYY-MM-DD')
    -- date_trunc('week') is Monday-based in PostgreSQL, which is the rule.
    when 'per_week' then to_char(date_trunc('week', p_at at time zone 'Asia/Singapore'), 'YYYY-MM-DD')
    when 'per_month' then to_char(p_at at time zone 'Asia/Singapore', 'YYYY-MM')
    else null end
$function$;

/**
 * May this customer take this service at this moment, given this history?
 *
 * The history is an ARGUMENT, not a lookup. There is no authoritative
 * appointment or completed-session table in this system yet, so a function that
 * went looking for one would be answering from nothing. When that table exists,
 * its caller passes it here and this needs no change.
 */
create or replace function public.therapy_service_frequency_ok(
  p_service_id uuid, p_at timestamptz, p_history timestamptz[] default '{}')
returns jsonb language plpgsql stable set search_path = public as $function$
declare
  s public.therapy_services%rowtype;
  v_count integer; v_window interval; v_blocking timestamptz; v_key text;
begin
  select * into s from public.therapy_services where id = p_service_id;
  if not found then
    return jsonb_build_object('allowed', false, 'reason', 'That service no longer exists.');
  end if;

  if s.frequency_kind = 'unrestricted' then
    return jsonb_build_object('allowed', true, 'reason', null, 'counted_in_period', 0);
  end if;

  if s.frequency_kind = 'per_hours' then
    if s.frequency_interval_hours is null then
      -- An unusable rule is not permission.
      return jsonb_build_object('allowed', false, 'reason', 'This service has no interval configured.');
    end if;
    v_window := make_interval(secs => s.frequency_interval_hours * 3600);
    select count(*), min(h) into v_count, v_blocking
      from unnest(coalesce(p_history, '{}')) h
     where h <= p_at and p_at - h < v_window;
    if v_count < s.frequency_max_per_period then
      return jsonb_build_object('allowed', true, 'reason', null, 'counted_in_period', v_count);
    end if;
    -- The session that has to age out is the (count - max + 1)th oldest in the
    -- window; with the usual max of 1 that is simply the most recent.
    select h into v_blocking from (
      select h from unnest(coalesce(p_history, '{}')) h
       where h <= p_at and p_at - h < v_window order by h desc
       limit s.frequency_max_per_period) x order by h asc limit 1;
    return jsonb_build_object('allowed', false, 'counted_in_period', v_count,
      -- Formatted the way therapy_frequency_description formats it, so a
      -- customer is not told "every 5.00 hours" in one place and "every 5
      -- hours" in another.
      'reason', format('Only %s session%s every %s hour%s. The last one started at %s.',
                       s.frequency_max_per_period,
                       case when s.frequency_max_per_period = 1 then '' else 's' end,
                       trim(trailing '.' from trim(trailing '0' from s.frequency_interval_hours::text)),
                       case when s.frequency_interval_hours = 1 then '' else 's' end,
                       to_char(v_blocking at time zone 'Asia/Singapore', 'YYYY-MM-DD HH24:MI')),
      'next_allowed_at', v_blocking + v_window);
  end if;

  v_key := public.sgt_period_key(p_at, s.frequency_kind);
  select count(*) into v_count
    from unnest(coalesce(p_history, '{}')) h
   where h <= p_at and public.sgt_period_key(h, s.frequency_kind) = v_key;

  if v_count < s.frequency_max_per_period then
    return jsonb_build_object('allowed', true, 'reason', null, 'counted_in_period', v_count);
  end if;
  return jsonb_build_object('allowed', false, 'counted_in_period', v_count,
    'reason', format('Already taken %s time(s) this calendar %s (Singapore), and the limit is %s.',
      v_count,
      case s.frequency_kind when 'per_day' then 'day' when 'per_week' then 'week' else 'month' end,
      s.frequency_max_per_period));
end $function$;

-- ---------------------------------------------------------------------
-- 4. Managing the catalogue. Owners and Managers only.
-- ---------------------------------------------------------------------
create or replace function public.upsert_therapy_service(
  p_id uuid, p_service_code text, p_name text,
  p_standard_price numeric, p_duration_minutes integer,
  p_frequency_kind text, p_frequency_max_per_period integer default 1,
  p_frequency_interval_hours numeric default null,
  p_description text default null, p_is_active boolean default false,
  p_notes text default null)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare v_id uuid; v_code text := lower(btrim(coalesce(p_service_code, '')));
begin
  if not public.is_manager_or_above() then
    raise exception 'Only an Owner or Manager can manage therapy services';
  end if;
  if coalesce(btrim(p_name), '') = '' then raise exception 'A service name is required'; end if;
  if v_code = '' then raise exception 'A service code is required'; end if;
  if p_standard_price is null or p_standard_price < 0 then
    raise exception 'Enter the standard selling price'; end if;
  if p_frequency_kind not in ('per_day','per_week','per_month','per_hours','unrestricted') then
    raise exception 'Choose how often this service may be taken'; end if;
  if p_frequency_kind = 'per_hours' and coalesce(p_frequency_interval_hours, 0) <= 0 then
    raise exception 'Enter the number of hours between sessions, for example 5'; end if;

  -- Refused rather than silently saved as a draft: an active service with no
  -- duration cannot be put in a calendar, and the caller should know now.
  if p_is_active and p_duration_minutes is null then
    raise exception 'A service needs a duration in minutes before it can be made active';
  end if;

  if exists (select 1 from public.therapy_services s
              where lower(s.service_code) = v_code and s.deleted_at is null
                and (p_id is null or s.id <> p_id)) then
    raise exception 'Another service already uses the code %', p_service_code;
  end if;

  if p_id is null then
    insert into public.therapy_services (service_code, name, description, standard_price,
      duration_minutes, frequency_kind, frequency_max_per_period, frequency_interval_hours,
      is_active, notes, created_by, updated_by)
    values (btrim(p_service_code), btrim(p_name), nullif(btrim(p_description), ''), p_standard_price,
      p_duration_minutes, p_frequency_kind, coalesce(p_frequency_max_per_period, 1),
      case when p_frequency_kind = 'per_hours' then p_frequency_interval_hours else null end,
      coalesce(p_is_active, false), nullif(btrim(p_notes), ''), auth.uid(), auth.uid())
    returning id into v_id;
  else
    update public.therapy_services
       set service_code = btrim(p_service_code), name = btrim(p_name),
           description = nullif(btrim(p_description), ''), standard_price = p_standard_price,
           duration_minutes = p_duration_minutes, frequency_kind = p_frequency_kind,
           frequency_max_per_period = coalesce(p_frequency_max_per_period, 1),
           frequency_interval_hours =
             case when p_frequency_kind = 'per_hours' then p_frequency_interval_hours else null end,
           is_active = coalesce(p_is_active, false), notes = nullif(btrim(p_notes), ''),
           updated_by = auth.uid(), updated_at = now()
     where id = p_id and deleted_at is null
    returning id into v_id;
    if v_id is null then raise exception 'That service no longer exists'; end if;
  end if;

  insert into public.audit_logs (table_name, record_id, action, new_data, changed_by)
  values ('therapy_services', v_id, case when p_id is null then 'therapy_service_created' else 'therapy_service_updated' end,
          jsonb_build_object('code', p_service_code, 'name', p_name, 'price', p_standard_price,
                             'active', coalesce(p_is_active, false)), auth.uid());

  return jsonb_build_object('id', v_id, 'code', btrim(p_service_code));
end $function$;

create or replace function public.set_therapy_service_store(
  p_service_id uuid, p_store_id uuid, p_is_available boolean, p_price_override numeric default null)
returns void language plpgsql security definer set search_path = public as $function$
begin
  if not public.is_manager_or_above() then
    raise exception 'Only an Owner or Manager can manage therapy services'; end if;
  insert into public.therapy_service_stores (service_id, store_id, is_available, price_override)
  values (p_service_id, p_store_id, coalesce(p_is_available, true), p_price_override)
  on conflict (service_id, store_id) do update
    set is_available = excluded.is_available, price_override = excluded.price_override,
        updated_at = now();
end $function$;

/**
 * Deactivating, not deleting.
 *
 * A service that has been sold is part of somebody's history and part of an
 * issued voucher's snapshot. Removing the row would orphan both, so it is
 * archived: it stops being sellable and stays readable.
 */
create or replace function public.archive_therapy_service(p_id uuid, p_reason text default null)
returns void language plpgsql security definer set search_path = public as $function$
begin
  if not public.is_manager_or_above() then
    raise exception 'Only an Owner or Manager can manage therapy services'; end if;
  update public.therapy_services
     set is_active = false, deleted_at = now(), updated_by = auth.uid(), updated_at = now()
   where id = p_id and deleted_at is null;
  insert into public.audit_logs (table_name, record_id, action, new_data, changed_by)
  values ('therapy_services', p_id, 'therapy_service_archived',
          jsonb_build_object('reason', nullif(btrim(p_reason), '')), auth.uid());
end $function$;

-- ---------------------------------------------------------------------
-- 5. What the page reads.
-- ---------------------------------------------------------------------
create or replace function public.therapy_service_catalogue(
  p_store_id uuid default null, p_include_inactive boolean default false)
returns table (
  id uuid, service_code text, name text, description text,
  standard_price numeric, effective_price numeric, duration_minutes integer,
  frequency_kind text, frequency_max_per_period integer, frequency_interval_hours numeric,
  frequency_description text, is_active boolean, is_archived boolean,
  store_count integer, store_names text[], available_here boolean, has_price_override boolean,
  can_manage boolean)
language sql stable security definer set search_path = public as $function$
  select s.id, s.service_code, s.name, s.description,
         s.standard_price,
         coalesce(ss.price_override, s.standard_price),
         s.duration_minutes,
         s.frequency_kind, s.frequency_max_per_period, s.frequency_interval_hours,
         public.therapy_frequency_description(s.frequency_kind, s.frequency_max_per_period, s.frequency_interval_hours),
         s.is_active, s.deleted_at is not null,
         (select count(*)::integer from public.therapy_service_stores x
           where x.service_id = s.id and x.is_available),
         coalesce((select array_agg(st.name order by st.name)
                     from public.therapy_service_stores x
                     join public.stores st on st.id = x.store_id
                    where x.service_id = s.id and x.is_available), '{}'),
         coalesce(ss.is_available, false),
         ss.price_override is not null,
         public.is_manager_or_above()
    from public.therapy_services s
    left join public.therapy_service_stores ss
      on ss.service_id = s.id and ss.store_id = p_store_id
   where (p_include_inactive or (s.is_active and s.deleted_at is null))
     and (p_store_id is null or coalesce(ss.is_available, false) or p_include_inactive)
   order by s.name
$function$;

-- ---------------------------------------------------------------------
-- 6. Access.
-- ---------------------------------------------------------------------
alter table public.therapy_services enable row level security;
alter table public.therapy_service_stores enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where tablename = 'therapy_services' and policyname = 'read services') then
    create policy "read services" on public.therapy_services for select to authenticated using (true);
  end if;
  if not exists (select 1 from pg_policies where tablename = 'therapy_service_stores' and policyname = 'read service stores') then
    create policy "read service stores" on public.therapy_service_stores for select to authenticated using (true);
  end if;
end $$;

-- No write policy: every change goes through the functions above, which check
-- the caller's role first.

grant select on public.therapy_services, public.therapy_service_stores to authenticated;
grant execute on function public.therapy_service_price(uuid,uuid) to authenticated;
grant execute on function public.therapy_service_available_at(uuid,uuid) to authenticated;
grant execute on function public.therapy_frequency_description(text,integer,numeric) to authenticated;
grant execute on function public.sgt_period_key(timestamptz,text) to authenticated;
grant execute on function public.therapy_service_frequency_ok(uuid,timestamptz,timestamptz[]) to authenticated;
grant execute on function public.upsert_therapy_service(uuid,text,text,numeric,integer,text,integer,numeric,text,boolean,text) to authenticated;
grant execute on function public.set_therapy_service_store(uuid,uuid,boolean,numeric) to authenticated;
grant execute on function public.archive_therapy_service(uuid,text) to authenticated;
grant execute on function public.therapy_service_catalogue(uuid,boolean) to authenticated;
