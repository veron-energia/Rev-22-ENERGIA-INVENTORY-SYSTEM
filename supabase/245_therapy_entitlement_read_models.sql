-- =====================================================================
-- ENERGIA — WHAT A CUSTOMER CAN ACTUALLY TAKE
--
-- After 240-244 a customer's therapy rights can come from three unrelated
-- places, and they are not interchangeable:
--
--   * an UNLIMITED period — any service, as often as each service allows,
--     until the period expires;
--   * PURCHASED SESSIONS — a counted number of one specific service;
--   * a VOUCHER — units whose eligibility is whatever was frozen at issue,
--     which may be one fixed service or a choice between several.
--
-- Reading these separately is how a counter assistant ends up telling somebody
-- they have "four therapies left" when three of them are Foot Detox and the
-- customer wants Power Recharge. This migration answers the question the way it
-- actually gets asked: what can this person have, of what, and for how long.
--
-- 222's therapy_customer_detail is NOT rewritten. It is composed with instead,
-- so the therapy work that owns it stays owned by it.
--
-- Section 2 is the permission-aware half. A calendar does not exist yet; these
-- are the read models it would call, and they answer for the CALLER — store
-- access is applied inside them, not left to the page.
--
-- Requires 240, 241 and 244. Additive, read-only: this migration creates no
-- table and writes no row.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. The three sources, in one shape.
--
-- 'eligibility' is the field that matters and the one a name cannot supply:
--
--   'any_service' — an unlimited period; the service catalogue is the limit
--   'fixed'       — this one service and no other
--   'choice'      — one of a named set
--
-- remaining is a COUNT for sessions and voucher units, and null for an
-- unlimited period, because "how many" is the wrong question there. A caller
-- that treats null as zero is wrong in an obvious way rather than a subtle one.
-- ---------------------------------------------------------------------
create or replace function public.therapy_customer_entitlements(
  p_customer_id uuid, p_as_of date default null)
returns table(
  source_kind text, source_id uuid, title text, detail text,
  eligibility text, service_ids uuid[], service_names text[],
  remaining integer, unit text,
  valid_until date, days_remaining integer, is_usable boolean, blocked_reason text)
language sql stable set search_path = public as $function$
with as_of as (select coalesce(p_as_of, public.sg_today()) as d),

-- Unlimited periods, purchased or earned. Both live in the same two tables the
-- therapy work already maintains; nothing here reinterprets them.
unlimited as (
  select 'unlimited'::text as source_kind, e.id as source_id,
         coalesce(p.name, 'Unlimited therapy') as title,
         coalesce(p.duration_months || ' month period', 'Unlimited period') as detail,
         'any_service'::text as eligibility,
         null::uuid[] as service_ids, null::text[] as service_names,
         null::integer as remaining, 'period'::text as unit,
         e.expiry_date as valid_until,
         e.status::text as status
    from public.purchased_therapy_entitlements e
    left join public.unlimited_therapy_packages p on p.id = e.package_id
   where e.customer_id = p_customer_id
     and e.status::text in ('active','scheduled','pending_activation')
),

-- Sessions bought outright. Counted, and tied to exactly one service.
sessions as (
  select 'sessions'::text, s.service_id,
         s.service_name_snapshot,
         case when s.service_minutes_snapshot is null then 'Purchased session'
              else s.service_minutes_snapshot || ' minute session' end,
         'fixed'::text,
         array[s.service_id], array[s.service_name_snapshot],
         sum(s.quantity_purchased - s.quantity_used)::integer,
         'session'::text,
         null::date,
         'active'::text
    from public.customer_therapy_sessions s
   where s.customer_id = p_customer_id and s.status = 'available'
   group by s.service_id, s.service_name_snapshot, s.service_minutes_snapshot
  having sum(s.quantity_purchased - s.quantity_used) > 0
),

-- Voucher units, read from the snapshot frozen at issue. A voucher with no
-- recorded rights is reported, not omitted and not assumed — see 241.
voucher_rights as (
  select r.reward_voucher_id, r.voucher_name, r.sessions_remaining, r.valid_until,
         r.rights_recorded, r.summary_text, r.definition_snapshot, r.status
    from public.customer_therapy_voucher_rights(p_customer_id, (select d from as_of)) r
   where r.status = 'held'
),
vouchers as (
  select 'voucher'::text, vr.reward_voucher_id, vr.voucher_name,
         coalesce(vr.summary_text, 'Voucher'),
         case
           when not vr.rights_recorded then 'unrecorded'
           -- One component offering one service is a fixed right; anything else
           -- gives the holder a choice, and saying otherwise would overstate it.
           when (select count(*) from jsonb_array_elements(vr.definition_snapshot->'components') c) = 1
            and (select jsonb_array_length(c->'services')
                   from jsonb_array_elements(vr.definition_snapshot->'components') c limit 1) = 1
             then 'fixed'
           else 'choice'
         end,
         (select array_agg(distinct (s->>'service_id')::uuid)
            from jsonb_array_elements(coalesce(vr.definition_snapshot->'components', '[]')) c,
                 jsonb_array_elements(c->'services') s),
         (select array_agg(distinct s->>'name' order by s->>'name')
            from jsonb_array_elements(coalesce(vr.definition_snapshot->'components', '[]')) c,
                 jsonb_array_elements(c->'services') s),
         vr.sessions_remaining, 'session'::text, vr.valid_until,
         'active'::text
    from voucher_rights vr
),
all_sources as (
  select * from unlimited union all select * from sessions union all select * from vouchers
)
select a.source_kind, a.source_id, a.title, a.detail, a.eligibility,
       a.service_ids, a.service_names, a.remaining, a.unit, a.valid_until,
       -- Inclusive, matching the expiry convention the therapy work settled on:
       -- a period ending today still has one day in it.
       case when a.valid_until is null then null
            when a.valid_until < (select d from as_of) then 0
            else (a.valid_until - (select d from as_of)) + 1 end,
       (a.status = 'active'
        and (a.valid_until is null or a.valid_until >= (select d from as_of))
        and (a.remaining is null or a.remaining > 0)
        and a.eligibility <> 'unrecorded'),
       case
         when a.eligibility = 'unrecorded'
           then 'This voucher has no recorded therapy-service rights. Someone has to confirm what it gives.'
         when a.status <> 'active'
           then 'Not active yet — this entitlement is ' || replace(a.status, '_', ' ') || '.'
         when a.valid_until is not null and a.valid_until < (select d from as_of)
           then 'Expired on ' || a.valid_until || '.'
         when a.remaining is not null and a.remaining <= 0
           then 'Nothing left on this one.'
         else null end
  from all_sources a
 order by a.source_kind, a.title
$function$;

-- The same three sources, totalled — the line a summary screen shows.
create or replace function public.therapy_customer_service_summary(
  p_customer_id uuid, p_as_of date default null)
returns jsonb language sql stable set search_path = public as $function$
  select jsonb_build_object(
    'as_of', coalesce(p_as_of, public.sg_today()),
    'has_unlimited', exists (select 1 from public.therapy_customer_entitlements(p_customer_id, p_as_of) e
                              where e.source_kind = 'unlimited' and e.is_usable),
    'unlimited_expires', (select min(e.valid_until) from public.therapy_customer_entitlements(p_customer_id, p_as_of) e
                           where e.source_kind = 'unlimited' and e.is_usable),
    'purchased_sessions', coalesce((select sum(e.remaining) from public.therapy_customer_entitlements(p_customer_id, p_as_of) e
                                     where e.source_kind = 'sessions' and e.is_usable), 0),
    'voucher_sessions', coalesce((select sum(e.remaining) from public.therapy_customer_entitlements(p_customer_id, p_as_of) e
                                   where e.source_kind = 'voucher' and e.is_usable), 0),
    -- Counted separately and never added in: an unrecorded voucher is a
    -- question, and adding it to a total would answer it.
    'vouchers_needing_review', (select count(*) from public.therapy_customer_entitlements(p_customer_id, p_as_of) e
                                 where e.eligibility = 'unrecorded'),
    'entitlements', coalesce((select jsonb_agg(to_jsonb(e))
                                from public.therapy_customer_entitlements(p_customer_id, p_as_of) e), '[]'::jsonb))
$function$;

-- 222's detail, with the new sources beside it. Composed, not rewritten.
create or replace function public.therapy_customer_overview(p_customer_id uuid)
returns jsonb language sql stable security definer set search_path = public as $function$
  select public.therapy_customer_detail(p_customer_id)
      || jsonb_build_object('services', public.therapy_customer_service_summary(p_customer_id))
$function$;

-- ---------------------------------------------------------------------
-- 2. What a calendar would ask, answered for the CALLER.
--
-- There is no calendar and no appointment table. These exist so that when one
-- is built the permission question is already settled in the database rather
-- than re-decided in a page — the mistake that lets a store see another store's
-- customers.
-- ---------------------------------------------------------------------

-- What could be booked at this store, by someone with access to it.
create or replace function public.therapy_calendar_services(p_store_id uuid)
returns table(service_id uuid, service_code text, name text, duration_minutes integer,
              price numeric, frequency_kind text, frequency_max_per_period integer,
              frequency_interval_hours numeric, frequency_text text)
language sql stable security definer set search_path = public as $function$
  select s.id, s.service_code, s.name, s.duration_minutes,
         public.therapy_service_price(s.id, p_store_id),
         s.frequency_kind, s.frequency_max_per_period, s.frequency_interval_hours,
         public.therapy_frequency_description(s.frequency_kind, s.frequency_max_per_period,
                                              s.frequency_interval_hours)
    from public.therapy_services s
    join public.therapy_service_stores ss on ss.service_id = s.id and ss.store_id = p_store_id
   where s.is_active and s.deleted_at is null and ss.is_available
     -- The access check lives here. A caller without it gets no rows, not a
     -- filtered-in-the-browser list.
     and public.user_has_store_access(p_store_id)
   order by s.name
$function$;

/**
 * What could pay for a session of this service, for this customer, at this
 * store — and whether the frequency rule allows it right now.
 *
 * The session history is an ARGUMENT for the same reason it is in 240: there is
 * no authoritative record of completed sessions, and a function that went
 * looking for one would be answering from nothing. When that record exists its
 * caller passes it here.
 */
create or replace function public.therapy_booking_options(
  p_customer_id uuid, p_service_id uuid, p_store_id uuid,
  p_at timestamptz default now(), p_history timestamptz[] default '{}')
returns jsonb language plpgsql stable security definer set search_path = public as $function$
declare v_service public.therapy_services%rowtype; v_freq jsonb; v_options jsonb;
begin
  if not public.user_has_store_access(p_store_id) then
    -- Refused rather than empty: an empty list reads as "nothing available",
    -- which is a different and misleading answer.
    raise exception 'You do not have access to this store' using errcode = '42501';
  end if;

  select * into v_service from public.therapy_services
   where id = p_service_id and deleted_at is null;
  if not found then
    return jsonb_build_object('available', false, 'reason', 'That service no longer exists.');
  end if;
  if not public.therapy_service_available_at(p_service_id, p_store_id) then
    return jsonb_build_object('available', false,
      'reason', format('%s is not offered at this store.', v_service.name));
  end if;

  v_freq := public.therapy_service_frequency_ok(p_service_id, p_at, p_history);

  select coalesce(jsonb_agg(to_jsonb(e) order by e.source_kind), '[]'::jsonb) into v_options
    from public.therapy_customer_entitlements(p_customer_id) e
   where e.is_usable
     and (e.eligibility = 'any_service'
          or p_service_id = any(coalesce(e.service_ids, '{}'::uuid[])));

  return jsonb_build_object(
    'available', true,
    'service', jsonb_build_object('id', v_service.id, 'name', v_service.name,
      'duration_minutes', v_service.duration_minutes,
      'price', public.therapy_service_price(p_service_id, p_store_id)),
    'frequency', v_freq,
    -- Both halves are reported. An entitlement that exists but is blocked by
    -- frequency is a different conversation from having none at all, and
    -- collapsing them would hide which one it is.
    'entitlements', v_options,
    'payable_without_charge', jsonb_array_length(v_options) > 0 and (v_freq->>'allowed')::boolean,
    'reason', case
      when jsonb_array_length(v_options) = 0
        then 'Nothing this customer holds covers this service — it would be a paid session.'
      when not (v_freq->>'allowed')::boolean then v_freq->>'reason'
      else null end);
end $function$;

grant execute on function public.therapy_customer_entitlements(uuid,date) to authenticated;
grant execute on function public.therapy_customer_service_summary(uuid,date) to authenticated;
grant execute on function public.therapy_customer_overview(uuid) to authenticated;
grant execute on function public.therapy_calendar_services(uuid) to authenticated;
grant execute on function public.therapy_booking_options(uuid,uuid,uuid,timestamptz,timestamptz[]) to authenticated;
