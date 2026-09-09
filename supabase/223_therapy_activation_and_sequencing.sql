-- =====================================================================
-- ENERGIA — ACTIVATION WITH CLOSURE EXTENSIONS, AND CONSECUTIVE PACKAGES
--
-- Two changes to purchased unlimited therapy:
--
--   1. Activating one now applies the closure extension, using the holiday
--      calendar assigned to it and the membership_expiry convention it has
--      always used. Nothing already activated moves; this affects activations
--      from here on, and the audited recalculation in migration 220 is the
--      only thing that touches existing rows.
--
--   2. A customer who already holds unlimited therapy gets a suggested start
--      the day after their latest adjusted expiry, so a second package extends
--      their access rather than running alongside it and quietly wasting half.
--      It is a suggestion: staff can still choose any date, and an overlap is
--      shown as an overlap rather than created by accident.
--
-- Additive. Run AFTER 220, 221 and 222. Safe to run more than once.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Where a new period should start, and what it would collide with.
-- ---------------------------------------------------------------------
create or replace function public.therapy_next_available_start(
  p_customer_id uuid, p_earliest date default null)
returns jsonb language plpgsql stable security definer set search_path = public as $function$
declare
  v_earliest date := coalesce(p_earliest, public.sg_today());
  v_latest date; v_suggested date; v_holds jsonb;
begin
  select max(u.expiry_date) into v_latest
    from (
      select expiry_date from public.purchased_therapy_entitlements
       where customer_id = p_customer_id and status in ('active','scheduled')
      union all
      select expiry_date from public.therapy_entitlements
       where customer_id = p_customer_id and status in ('active','scheduled')
         and coalesce(entitlement_kind,'unlimited') = 'unlimited'
    ) u;

  -- The day after the latest ADJUSTED expiry — the extension is already in it,
  -- so a closure that lengthened the first package pushes the second along too.
  v_suggested := case when v_latest is null or v_latest < v_earliest
                      then v_earliest else v_latest + 1 end;

  select coalesce(jsonb_agg(jsonb_build_object(
           'kind', u.k, 'entitlement_no', u.entitlement_no, 'status', u.status,
           'activation_date', u.activation_date, 'expiry_date', u.expiry_date)
         order by u.expiry_date), '[]'::jsonb)
    into v_holds
    from (
      select 'purchased'::text as k, entitlement_no, status, activation_date, expiry_date
        from public.purchased_therapy_entitlements
       where customer_id = p_customer_id and status in ('active','scheduled')
      union all
      select 'legacy', entitlement_no, status, activation_date, expiry_date
        from public.therapy_entitlements
       where customer_id = p_customer_id and status in ('active','scheduled')
         and coalesce(entitlement_kind,'unlimited') = 'unlimited'
    ) u;

  return jsonb_build_object(
    'suggested_start', v_suggested,
    'earliest_allowed', v_earliest,
    'latest_existing_expiry', v_latest,
    'would_overlap_if_started_today', v_latest is not null and v_latest >= v_earliest,
    'existing', v_holds);
end $function$;

-- ---------------------------------------------------------------------
-- 2. Activation, with the closure extension applied.
--
-- Replaces migration 53's version. Same signature for the first three
-- arguments so every existing caller keeps working unchanged; the holiday
-- country is optional and, when omitted, the entitlement's own assignment is
-- used. Without either, the base expiry stands and the entitlement is reported
-- as needing a country rather than being given a silent zero-holiday calendar.
-- ---------------------------------------------------------------------
drop function if exists public.activate_purchased_therapy(uuid, date, text);

create or replace function public.activate_purchased_therapy(
  p_entitlement_id uuid, p_activation_date date default null, p_reason text default null,
  p_holiday_country text default null, p_holiday_region text default null,
  p_allow_overlap boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare
  e public.purchased_therapy_entitlements%rowtype;
  v_today date := public.sg_today();
  v_act date; v_calc record; v_country text; v_region text;
  v_next jsonb; v_overlaps boolean;
begin
  select * into e from public.purchased_therapy_entitlements where id = p_entitlement_id for update;
  if not found then raise exception 'Entitlement not found'; end if;
  if not public.user_has_store_access(e.store_id) then raise exception 'No access to this store'; end if;
  if e.status in ('active','expired','cancelled','refunded') then
    raise exception 'Entitlement is already %', e.status; end if;

  v_act := coalesce(p_activation_date, v_today);
  if v_act > e.activation_deadline then
    raise exception 'Activation must occur within one year of purchase (deadline %)', e.activation_deadline; end if;
  if v_act < v_today then raise exception 'Activation date cannot be in the past'; end if;

  -- An overlap is allowed, but only deliberately. Two periods running at once
  -- means the customer is paying twice for the same days.
  v_next := public.therapy_next_available_start(e.customer_id, v_today);
  v_overlaps := (v_next->>'latest_existing_expiry') is not null
                and v_act <= (v_next->>'latest_existing_expiry')::date;
  if v_overlaps and not p_allow_overlap then
    return jsonb_build_object('activated', false, 'requires_confirmation', true,
      'reason', 'This customer already has unlimited therapy running on that date.',
      'suggested_start', (v_next->>'suggested_start')::date,
      'existing', v_next->'existing');
  end if;

  v_country := coalesce(p_holiday_country, e.holiday_country);
  v_region  := coalesce(p_holiday_region, e.holiday_region);

  -- 'purchased': membership_expiry, the convention this table has always used.
  select * into v_calc
    from public.therapy_adjusted_expiry(v_act, e.duration_months, v_country, v_region, 'purchased');

  update public.purchased_therapy_entitlements
     set activation_date = v_act,
         base_expiry_date = v_calc.base_expiry,
         closure_days_added = coalesce(v_calc.added_days, 0),
         expiry_date = v_calc.adjusted_expiry,
         expiry_calculated_at = now(),
         holiday_country = v_country, holiday_region = v_region,
         holiday_country_source = coalesce(holiday_country_source,
           case when p_holiday_country is not null then 'manual' else null end),
         status = case when v_act > v_today then 'scheduled' else 'active' end,
         scheduled_date = case when v_act > v_today then v_act else scheduled_date end,
         updated_by = auth.uid(), updated_at = now()
   where id = p_entitlement_id;

  insert into public.therapy_expiry_adjustments (
    entitlement_kind, entitlement_id, customer_id, action, reason,
    new_country, new_region, old_expiry, new_expiry, base_expiry, days_added,
    performed_by, detail)
  values ('purchased', p_entitlement_id, e.customer_id, 'country_assigned', p_reason,
    v_country, v_region, e.expiry_date, v_calc.adjusted_expiry, v_calc.base_expiry,
    coalesce(v_calc.added_days, 0), auth.uid(),
    public.therapy_expiry_explanation(v_act, e.duration_months, v_country, v_region, 'purchased'));

  perform public.write_audit_ex('purchased_therapy_entitlements', p_entitlement_id,
    case when v_act > v_today then 'therapy_scheduled' else 'therapy_activated' end,
    jsonb_build_object('status', e.status),
    jsonb_build_object('activation', v_act, 'expiry', v_calc.adjusted_expiry,
                       'base_expiry', v_calc.base_expiry, 'closure_days_added', v_calc.added_days,
                       'holiday_country', v_country, 'overlap_confirmed', v_overlaps),
    'therapy', p_reason, e.store_id);

  return jsonb_build_object('activated', true,
    'status', case when v_act > v_today then 'scheduled' else 'active' end,
    'activation_date', v_act,
    'base_expiry', v_calc.base_expiry,
    'closure_days_added', coalesce(v_calc.added_days, 0),
    'expiry_date', v_calc.adjusted_expiry,
    'holiday_country', v_country, 'holiday_region', v_region,
    'coverage', public.therapy_calendar_gaps(v_act, v_calc.adjusted_expiry, v_country, v_region),
    'overlapped', v_overlaps);
end $function$;

-- ---------------------------------------------------------------------
-- 3. Successors whose start was derived from a predecessor that has moved.
--
-- Reported, never moved automatically: a start date a member of staff chose
-- deliberately is not the system's to change. The list is the workflow.
-- ---------------------------------------------------------------------
create or replace function public.therapy_successor_reconciliation()
returns table (customer_id uuid, customer_name text,
               predecessor_no text, predecessor_expiry date,
               successor_kind text, successor_id uuid, successor_no text,
               successor_start date, suggested_start date, gap_days integer,
               overlaps boolean)
language sql stable security definer set search_path = public as $function$
  with periods as (
    select 'purchased'::text as k, p.id, p.entitlement_no, p.customer_id, p.status,
           coalesce(p.activation_date, p.scheduled_date) as starts, p.expiry_date
      from public.purchased_therapy_entitlements p
     where p.status in ('active','scheduled')
    union all
    select 'legacy', l.id, l.entitlement_no, l.customer_id, l.status,
           l.activation_date, l.expiry_date
      from public.therapy_entitlements l
     where l.status in ('active','scheduled')
       and coalesce(l.entitlement_kind,'unlimited') = 'unlimited'
  )
  select s.customer_id, c.full_name,
         p.entitlement_no, p.expiry_date,
         s.k, s.id, s.entitlement_no, s.starts,
         p.expiry_date + 1,
         s.starts - (p.expiry_date + 1),
         s.starts <= p.expiry_date
    from periods s
    join periods p on p.customer_id = s.customer_id and p.id <> s.id
                  and p.expiry_date is not null and s.starts is not null
                  and p.starts < s.starts
    left join public.customers c on c.id = s.customer_id
   where s.starts <> p.expiry_date + 1                -- not already consecutive
     and public.is_manager_or_above()
     -- only the immediate predecessor
     and p.expiry_date = (select max(p2.expiry_date) from periods p2
                           where p2.customer_id = s.customer_id and p2.id <> s.id
                             and p2.starts < s.starts)
   order by c.full_name, s.starts
$function$;

grant execute on function public.therapy_next_available_start(uuid,date) to authenticated;
grant execute on function public.activate_purchased_therapy(uuid,date,text,text,text,boolean) to authenticated;
grant execute on function public.therapy_successor_reconciliation() to authenticated;
