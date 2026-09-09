-- =====================================================================
-- ENERGIA — UNLIMITED THERAPY: CLOSURE EXTENSIONS AND HOLIDAY CALENDARS
--
-- An unlimited-therapy package sells a period of access measured in calendar
-- months. When the business is shut on a day inside that period, the customer
-- loses a day they paid for, and gets it back at the end.
--
-- The rules, and the reasoning behind each:
--
--   * Sundays earn nothing. The business is closed on Sundays anyway, so a
--     Sunday takes nothing away. This is also why an expiry that lands on a
--     Sunday is left there: Sundays are part of the calendar month that was
--     sold, not days owed back.
--   * A public holiday or company closure on Monday-Saturday adds one day.
--   * One date, one day. A public holiday that is also a company closure, or
--     the same date recorded twice, is still one day of lost access.
--   * An officially observed substitute (Vesak on a Sunday, observed on the
--     Monday) is a separate date, and the Monday is the one that earns the day.
--   * Extending can uncover further closures, so it repeats until stable.
--
-- Expiry is INCLUSIVE — the last day the benefit can be used. That is the
-- existing convention in therapy_expiry() (start + months - 1 day) and it is
-- preserved here rather than reinterpreted, so no live entitlement moves.
--
-- All dates are Singapore business dates (public.sg_today()). Holiday matching
-- is date-only: a stored date equals an entitlement date or it does not, with
-- no timestamps and therefore no timezone able to shift it by a day.
--
-- Mirrored by src/lib/therapy/expiry.mjs. scripts/therapy/tests/database.mjs
-- asserts the two agree, because one rule with two implementations drifts.
--
-- Additive. Creates no data beyond the country rows, changes no existing
-- expiry, and is safe to run more than once. Run AFTER 53, 72 and 74.
-- =====================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------
-- 1. Countries whose calendars this system knows about.
--
-- A country is listed here whether or not its calendar is filled in. That is
-- the point: an unconfigured country has to be visibly unconfigured, because
-- treating "no holidays recorded" as "no holidays" silently short-changes a
-- customer.
-- ---------------------------------------------------------------------
create table if not exists public.therapy_holiday_countries (
  code text primary key check (code ~ '^[A-Z]{2}$'),
  name text not null,
  is_active boolean not null default true,
  requires_region boolean not null default false,   -- regional calendars matter here
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.therapy_holiday_countries (code, name, requires_region, notes) values
  ('SG', 'Singapore', false, 'Gazetted public holidays apply nationwide.'),
  ('MY', 'Malaysia', true,  'Holidays vary by state; a region must be chosen before an expiry can be called verified.'),
  ('ID', 'Indonesia', false, 'Calendar not configured yet.'),
  ('CN', 'China', false, 'Calendar not configured yet.'),
  ('IN', 'India', true,  'Holidays vary by state; a region must be chosen.'),
  ('TH', 'Thailand', false, 'Calendar not configured yet.'),
  ('VN', 'Vietnam', false, 'Calendar not configured yet.'),
  ('PH', 'Philippines', false, 'Calendar not configured yet.'),
  ('AU', 'Australia', true, 'Holidays vary by state; a region must be chosen.'),
  ('GB', 'United Kingdom', true, 'England/Wales, Scotland and Northern Ireland differ.')
on conflict (code) do nothing;

-- ---------------------------------------------------------------------
-- 2. The dates themselves.
--
-- country_code null means every country — a company-wide shutdown. A row with
-- a country applies only to entitlements assigned to that country, so one
-- country's holiday can never extend everybody.
-- ---------------------------------------------------------------------
create table if not exists public.therapy_closure_dates (
  id uuid primary key default gen_random_uuid(),
  closure_date date not null,
  kind text not null check (kind in ('public_holiday', 'company_closure')),
  name text not null,
  country_code text references public.therapy_holiday_countries(code),
  region text,
  -- The date this row is the observed substitute for, when it is one. Kept so
  -- the pair can be explained: the Sunday earns nothing, the Monday earns a day.
  observed_for date,
  source text,                     -- e.g. 'mom.gov.sg gazette'
  source_reference text,           -- URL or document reference
  reason text,                     -- why a company closure was declared
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- One row per date per scope. coalesce, not plain columns: in a unique index
-- null never equals null, so two "all countries" rows for one date would both
-- be allowed and the date would still only count once — a silent inconsistency.
create unique index if not exists uq_therapy_closure_scope
  on public.therapy_closure_dates
     (closure_date, kind, coalesce(country_code, '*'), coalesce(region, '*'))
  where deleted_at is null;

create index if not exists idx_therapy_closure_lookup
  on public.therapy_closure_dates (closure_date)
  where deleted_at is null;

-- ---------------------------------------------------------------------
-- 3. Which years are actually covered.
--
-- Without this, an entitlement running through an unfilled year gets a
-- confident-looking expiry computed from nothing. A year is covered only when
-- someone recorded that they checked it against a source.
-- ---------------------------------------------------------------------
create table if not exists public.therapy_calendar_coverage (
  country_code text not null references public.therapy_holiday_countries(code),
  year integer not null check (year between 2000 and 2100),
  region text,
  is_verified boolean not null default false,
  source text,
  source_reference text,
  confirmed_by uuid references public.profiles(id),
  confirmed_at timestamptz,
  notes text,
  primary key (country_code, year, region)
);

-- A null region is not the same as an absent one for a primary key, so give it
-- a concrete value. '*' means "the country as a whole".
alter table public.therapy_calendar_coverage
  alter column region set default '*';

-- ---------------------------------------------------------------------
-- 4. What each entitlement was assigned, frozen at activation.
--
-- The country is a snapshot. A customer correcting their phone number later
-- must not silently move an expiry they were already given, so the assignment
-- lives on the entitlement, not on a join to the customer's current phone.
--
-- expiry_date keeps its existing meaning — the effective, inclusive last day —
-- so every existing query keeps working. The base and the added days are stored
-- beside it so the adjustment can be explained and recomputed from scratch.
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['purchased_therapy_entitlements', 'therapy_entitlements'] loop
    execute format($f$
      alter table public.%I
        add column if not exists holiday_country text references public.therapy_holiday_countries(code),
        add column if not exists holiday_region text,
        add column if not exists holiday_country_source text,   -- 'phone' | 'manual' | 'default'
        add column if not exists base_expiry_date date,
        add column if not exists closure_days_added integer not null default 0,
        add column if not exists expiry_calculated_at timestamptz
    $f$, t);
  end loop;
end $$;

-- Audit trail for every holiday assignment and every expiry movement. Separate
-- from audit_logs so the before/after dates are queryable rather than buried in
-- jsonb, and so a recalculation can be explained to a customer.
create table if not exists public.therapy_expiry_adjustments (
  id uuid primary key default gen_random_uuid(),
  entitlement_kind text not null check (entitlement_kind in ('purchased', 'legacy')),
  entitlement_id uuid not null,
  customer_id uuid references public.customers(id),
  action text not null check (action in
    ('country_assigned', 'country_corrected', 'recalculated', 'calendar_changed', 'reconciled_successor')),
  reason text,
  old_country text, new_country text,
  old_region text, new_region text,
  old_expiry date, new_expiry date,
  base_expiry date, days_added integer,
  detail jsonb,
  performed_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create index if not exists idx_therapy_expiry_adj_ent
  on public.therapy_expiry_adjustments (entitlement_kind, entitlement_id, created_at desc);

-- ---------------------------------------------------------------------
-- 5. The calculation. This is the SQL half of the mirrored pair.
-- ---------------------------------------------------------------------

-- The closure dates that apply to one assignment, in one window.
--
-- Region handling is deliberately strict: a region-specific closure applies
-- only when the entitlement names that same region. An entitlement with no
-- region does not quietly collect every region's holidays — it is reported as
-- needing configuration instead (see therapy_calendar_gaps).
create or replace function public.therapy_applicable_closures(
  p_from date, p_to date, p_country text default null, p_region text default null)
returns table (closure_date date, kind text, name text, country_code text,
               region text, observed_for date, source text)
language sql stable set search_path = public as $function$
  select d.closure_date, d.kind, d.name, d.country_code, d.region, d.observed_for, d.source
    from public.therapy_closure_dates d
   where d.deleted_at is null
     and d.closure_date >= p_from and d.closure_date <= p_to
     and (d.country_code is null or d.country_code = p_country)
     and (d.region is null or d.region = p_region)
   order by d.closure_date, d.kind, d.name
$function$;

-- Earlier drafts of this file created 4-argument forms of the two functions
-- below. Adding a defaulted parameter alongside them would make every existing
-- 4-argument call ambiguous, so the old shapes go first. On a database that has
-- never seen this file these drop nothing.
drop function if exists public.therapy_adjusted_expiry(date, integer, text, text);
drop function if exists public.therapy_expiry_explanation(date, integer, text, text);

-- The base expiry, from whichever convention the entitlement already uses.
--
-- These are NOT the same function, and the difference is real:
--
--   therapy_expiry('2024-02-29', 12)    = 2025-02-27
--   membership_expiry('2024-02-29', 12) = 2025-02-28
--
-- A 29 February start has no anniversary in a non-leap year. membership_expiry
-- treats the clamped 28 February as the full period and does not subtract a
-- day; therapy_expiry subtracts unconditionally. Purchased therapy has always
-- used the first, Legacy qualification the second, so customers hold live
-- entitlements computed both ways.
--
-- Picking one here would silently move somebody's expiry by a day, which is
-- exactly what this migration promises not to do. The convention travels with
-- the entitlement instead, and the closure extension is applied on top of
-- whichever base that entitlement was granted under.
create or replace function public.therapy_base_expiry(
  p_start date, p_months integer, p_convention text default 'legacy')
returns date language sql stable set search_path = public as $function$
  select case when p_convention = 'purchased'
              then public.membership_expiry(p_start, p_months)
              else public.therapy_expiry(p_start, p_months) end
$function$;

-- Adjusted expiry from the base and the calendar. Always recomputed from the
-- BASE, never from the current expiry, so running it repeatedly cannot add the
-- same days again.
create or replace function public.therapy_adjusted_expiry(
  p_activation date, p_months integer, p_country text default null,
  p_region text default null, p_convention text default 'legacy')
returns table (base_expiry date, adjusted_expiry date, added_days integer, iterations integer)
language plpgsql stable set search_path = public as $function$
declare
  v_base date;
  v_exp  date;
  v_applied date[] := '{}';
  v_new   date[];
  v_iter  integer := 0;
begin
  v_base := public.therapy_base_expiry(p_activation, p_months, p_convention);
  if v_base is null then
    return query select null::date, null::date, 0, 0;
    return;
  end if;

  v_exp := v_base;
  loop
    v_iter := v_iter + 1;
    select coalesce(array_agg(distinct c.closure_date), '{}')
      into v_new
      from public.therapy_applicable_closures(p_activation, v_exp, p_country, p_region) c
      -- Sunday is dow 0. A closure on a Sunday takes no working day away.
     where extract(dow from c.closure_date) <> 0
       and not (c.closure_date = any (v_applied));

    exit when coalesce(cardinality(v_new), 0) = 0;

    v_applied := v_applied || v_new;
    v_exp := v_exp + cardinality(v_new);

    -- Ten years of consecutive closures is not a calendar, it is a mistake.
    if v_iter > 3660 then
      raise exception 'Closure extension did not converge for % (% months, country %)',
        p_activation, p_months, coalesce(p_country, 'all');
    end if;
  end loop;

  return query select v_base, v_exp, coalesce(cardinality(v_applied), 0), v_iter;
end $function$;

-- The same answer, with the dates that justify it — for the expandable
-- explanation in the UI. Sundays that were skipped are included on purpose: a
-- customer asking "why didn't the holiday extend it" deserves an answer.
create or replace function public.therapy_expiry_explanation(
  p_activation date, p_months integer, p_country text default null,
  p_region text default null, p_convention text default 'legacy')
returns jsonb language plpgsql stable set search_path = public as $function$
declare
  v_calc record;
  v_applied jsonb;
  v_skipped jsonb;
begin
  select * into v_calc from public.therapy_adjusted_expiry(p_activation, p_months, p_country, p_region, p_convention);
  if v_calc.base_expiry is null then
    return jsonb_build_object('base_expiry', null, 'adjusted_expiry', null,
                              'added_days', 0, 'applied', '[]'::jsonb, 'skipped_sundays', '[]'::jsonb);
  end if;

  select coalesce(jsonb_agg(x order by x->>'date'), '[]'::jsonb) into v_applied
    from (
      select jsonb_build_object(
               'date', c.closure_date,
               'weekday', to_char(c.closure_date, 'Dy'),
               'names', array_agg(distinct c.name),
               'kinds', array_agg(distinct c.kind),
               'observed_for', max(c.observed_for),
               'scope', case when bool_or(c.country_code is null) then 'all countries'
                             else coalesce(max(c.country_code), '') end) as x
        from public.therapy_applicable_closures(p_activation, v_calc.adjusted_expiry, p_country, p_region) c
       where extract(dow from c.closure_date) <> 0
       group by c.closure_date
    ) s;

  select coalesce(jsonb_agg(x order by x->>'date'), '[]'::jsonb) into v_skipped
    from (
      select jsonb_build_object('date', c.closure_date, 'names', array_agg(distinct c.name),
                                'why', 'Sunday — the business is closed anyway') as x
        from public.therapy_applicable_closures(p_activation, v_calc.adjusted_expiry, p_country, p_region) c
       where extract(dow from c.closure_date) = 0
       group by c.closure_date
    ) s;

  return jsonb_build_object(
    'activation_date', p_activation,
    'months', p_months,
    'convention', p_convention,
    'country', p_country, 'region', p_region,
    'base_expiry', v_calc.base_expiry,
    'adjusted_expiry', v_calc.adjusted_expiry,
    'added_days', v_calc.added_days,
    'expiry_is_inclusive', true,
    'applied', v_applied,
    'skipped_sundays', v_skipped);
end $function$;

-- ---------------------------------------------------------------------
-- 6. Is the answer trustworthy? Coverage gaps, stated plainly.
-- ---------------------------------------------------------------------
create or replace function public.therapy_calendar_gaps(
  p_from date, p_to date, p_country text default null, p_region text default null)
returns jsonb language plpgsql stable set search_path = public as $function$
declare
  v_years integer[]; v_missing integer[]; v_country record; v_needs_region boolean := false;
begin
  if p_from is null or p_to is null then return jsonb_build_object('verified', false, 'reasons', jsonb_build_array('No period to check')); end if;

  select array_agg(y) into v_years
    from generate_series(extract(year from p_from)::int, extract(year from p_to)::int) y;

  if p_country is null then
    return jsonb_build_object('verified', false, 'country', null, 'years', to_jsonb(v_years),
      'missing_years', to_jsonb(v_years),
      'reasons', jsonb_build_array('No holiday country is assigned, so no calendar applies.'));
  end if;

  select * into v_country from public.therapy_holiday_countries where code = p_country;
  if not found then
    return jsonb_build_object('verified', false, 'country', p_country, 'years', to_jsonb(v_years),
      'missing_years', to_jsonb(v_years),
      'reasons', jsonb_build_array(format('Country %s is not configured.', p_country)));
  end if;

  v_needs_region := v_country.requires_region and p_region is null;

  select coalesce(array_agg(y order by y), '{}') into v_missing
    from unnest(v_years) y
   where not exists (
     select 1 from public.therapy_calendar_coverage c
      where c.country_code = p_country and c.year = y and c.is_verified
        and c.region = coalesce(p_region, '*'));

  return jsonb_build_object(
    'verified', coalesce(cardinality(v_missing), 0) = 0 and not v_needs_region,
    'country', p_country, 'region', p_region,
    'requires_region', v_country.requires_region,
    'years', to_jsonb(v_years),
    'missing_years', to_jsonb(v_missing),
    'reasons', (
      case when coalesce(cardinality(v_missing), 0) = 0 and not v_needs_region then '[]'::jsonb
      else coalesce((select jsonb_agg(r) from (
        select format('%s has no verified holiday calendar for %s.', p_country, y) as r
          from unnest(v_missing) y
        union all
        select format('%s holidays vary by region and no region is assigned.', p_country)
         where v_needs_region) z), '[]'::jsonb) end));
end $function$;

-- ---------------------------------------------------------------------
-- 7. Assigning a country.
--
-- The suggestion comes from the customer's phone, computed by the existing
-- parser in src/lib/customer-phones/normalize.mjs and passed in. It is NOT
-- reimplemented here: a second dialling-code table in SQL would drift from the
-- one the rest of the system uses, and a phone number is only ever a
-- suggestion anyway — it is not proof of where someone lives or attends.
--
-- So the database's job is to record the decision, validate it, and refuse to
-- invent one. An entitlement with no country is reported as needing a decision,
-- never quietly treated as a country with no holidays.
-- ---------------------------------------------------------------------
create or replace function public.therapy_assign_holiday_country(
  p_entitlement_kind text,          -- 'purchased' | 'legacy'
  p_entitlement_id uuid,
  p_country text,
  p_region text default null,
  p_reason text default null,
  p_source text default 'manual')   -- 'phone' | 'manual' | 'default'
returns jsonb language plpgsql security definer set search_path = public as $function$
declare
  v_tbl text; v_row record; v_calc record; v_old_expiry date; v_new_expiry date;
  v_months integer; v_activation date; v_status text; v_customer uuid;
begin
  if not public.is_manager_or_above() then
    raise exception 'Only an Owner or Manager can assign a holiday calendar';
  end if;
  if p_entitlement_kind not in ('purchased', 'legacy') then
    raise exception 'Unknown entitlement kind %', p_entitlement_kind;
  end if;
  if p_country is not null and not exists (
       select 1 from public.therapy_holiday_countries where code = p_country and is_active) then
    raise exception 'Country % is not a configured holiday country', p_country;
  end if;

  v_tbl := case p_entitlement_kind when 'purchased'
             then 'purchased_therapy_entitlements' else 'therapy_entitlements' end;

  execute format($f$
    select customer_id, activation_date, expiry_date, status,
           %s as months, holiday_country, holiday_region
      from public.%I where id = $1 for update
  $f$, case p_entitlement_kind when 'purchased' then 'duration_months' else 'duration_months' end, v_tbl)
    into v_row using p_entitlement_id;

  if v_row is null then raise exception 'Entitlement not found'; end if;

  -- An entitlement that is over stays over. Correcting a calendar does not
  -- bring a finished benefit back to life.
  if v_row.status in ('expired', 'cancelled', 'refunded') then
    raise exception 'This entitlement is % and cannot be recalculated', v_row.status;
  end if;

  v_customer := v_row.customer_id;
  v_activation := v_row.activation_date;
  v_months := v_row.months;
  v_old_expiry := v_row.expiry_date;

  -- A correction to an ALREADY ACTIVE entitlement needs a reason on the record.
  if v_row.status = 'active' and v_row.holiday_country is not null
     and v_row.holiday_country is distinct from p_country
     and coalesce(nullif(btrim(p_reason), ''), '') = '' then
    raise exception 'Correcting the holiday calendar of an active entitlement requires a reason';
  end if;

  if v_activation is not null and v_months is not null then
    select * into v_calc from public.therapy_adjusted_expiry(
      v_activation, v_months, p_country, p_region, p_entitlement_kind);
    v_new_expiry := v_calc.adjusted_expiry;

    -- Never silently shorten what was already granted. A shorter result is
    -- reported back to the caller, which must go through the explicit
    -- correction path with its own confirmation.
    if v_old_expiry is not null and v_new_expiry < v_old_expiry then
      return jsonb_build_object(
        'applied', false, 'requires_confirmation', true,
        'reason', 'This assignment would shorten an expiry that has already been granted.',
        'old_expiry', v_old_expiry, 'new_expiry', v_new_expiry,
        'base_expiry', v_calc.base_expiry, 'days_added', v_calc.added_days);
    end if;
  end if;

  execute format($f$
    update public.%I
       set holiday_country = $1, holiday_region = $2, holiday_country_source = $3,
           base_expiry_date = coalesce($4, base_expiry_date),
           closure_days_added = coalesce($5, closure_days_added),
           expiry_date = coalesce($6, expiry_date),
           expiry_calculated_at = now()
     where id = $7
  $f$, v_tbl)
    using p_country, p_region, p_source, v_calc.base_expiry, v_calc.added_days,
          v_new_expiry, p_entitlement_id;

  insert into public.therapy_expiry_adjustments (
    entitlement_kind, entitlement_id, customer_id, action, reason,
    old_country, new_country, old_region, new_region,
    old_expiry, new_expiry, base_expiry, days_added, performed_by, detail)
  values (p_entitlement_kind, p_entitlement_id, v_customer,
    case when v_row.holiday_country is null then 'country_assigned' else 'country_corrected' end,
    nullif(btrim(p_reason), ''),
    v_row.holiday_country, p_country, v_row.holiday_region, p_region,
    v_old_expiry, v_new_expiry, v_calc.base_expiry, v_calc.added_days, auth.uid(),
    public.therapy_expiry_explanation(v_activation, v_months, p_country, p_region, p_entitlement_kind));

  return jsonb_build_object(
    'applied', true, 'country', p_country, 'region', p_region,
    'old_expiry', v_old_expiry, 'new_expiry', v_new_expiry,
    'base_expiry', v_calc.base_expiry, 'days_added', v_calc.added_days,
    'coverage', public.therapy_calendar_gaps(v_activation, v_new_expiry, p_country, p_region));
end $function$;

-- The before/after a correction would produce, without making it. This is what
-- the confirmation dialog shows.
create or replace function public.therapy_preview_country_change(
  p_entitlement_kind text, p_entitlement_id uuid,
  p_country text, p_region text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $function$
declare v_tbl text; v_row record; v_calc record;
begin
  v_tbl := case p_entitlement_kind when 'purchased'
             then 'purchased_therapy_entitlements' else 'therapy_entitlements' end;
  execute format($f$
    select customer_id, activation_date, expiry_date, status, duration_months as months,
           holiday_country, holiday_region, base_expiry_date
      from public.%I where id = $1
  $f$, v_tbl) into v_row using p_entitlement_id;
  if v_row is null then raise exception 'Entitlement not found'; end if;

  select * into v_calc
    from public.therapy_adjusted_expiry(v_row.activation_date, v_row.months, p_country, p_region,
                                        p_entitlement_kind);

  return jsonb_build_object(
    'status', v_row.status,
    'from', jsonb_build_object('country', v_row.holiday_country, 'region', v_row.holiday_region,
                               'expiry', v_row.expiry_date),
    'to',   jsonb_build_object('country', p_country, 'region', p_region,
                               'expiry', v_calc.adjusted_expiry,
                               'base_expiry', v_calc.base_expiry, 'days_added', v_calc.added_days),
    'shortens', v_row.expiry_date is not null and v_calc.adjusted_expiry < v_row.expiry_date,
    'explanation', public.therapy_expiry_explanation(v_row.activation_date, v_row.months,
                                                     p_country, p_region, p_entitlement_kind),
    'coverage', public.therapy_calendar_gaps(v_row.activation_date, v_calc.adjusted_expiry, p_country, p_region));
end $function$;

-- ---------------------------------------------------------------------
-- 8. Historical data: look before touching anything.
--
-- Every active and scheduled unlimited entitlement, what its expiry would
-- become, and what is uncertain about it. Nothing is written.
-- ---------------------------------------------------------------------
create or replace function public.therapy_recalculation_preview(
  p_kind text default null,          -- null = both
  p_customer_id uuid default null)
returns table (
  entitlement_kind text, entitlement_id uuid, entitlement_no text,
  customer_id uuid, customer_name text, status text,
  activation_date date, months integer,
  holiday_country text, holiday_region text,
  current_expiry date, base_expiry date, proposed_expiry date,
  days_added integer, change_days integer,
  shortens boolean, needs_country boolean, coverage jsonb)
language sql stable security definer set search_path = public as $function$
  with rows as (
    select 'purchased'::text as k, p.id, p.entitlement_no, p.customer_id, p.status,
           p.activation_date, p.duration_months, p.holiday_country, p.holiday_region, p.expiry_date
      from public.purchased_therapy_entitlements p
     where p.status in ('active', 'scheduled')
       and (p_kind is null or p_kind = 'purchased')
    union all
    select 'legacy', l.id, l.entitlement_no, l.customer_id, l.status,
           l.activation_date, l.duration_months, l.holiday_country, l.holiday_region, l.expiry_date
      from public.therapy_entitlements l
     where l.status in ('active', 'scheduled')
       and coalesce(l.entitlement_kind, 'unlimited') = 'unlimited'
       and (p_kind is null or p_kind = 'legacy')
  )
  select r.k, r.id, r.entitlement_no, r.customer_id, c.full_name, r.status,
         r.activation_date, r.duration_months,
         r.holiday_country, r.holiday_region,
         r.expiry_date, calc.base_expiry, calc.adjusted_expiry, calc.added_days,
         case when calc.adjusted_expiry is null or r.expiry_date is null then null
              else calc.adjusted_expiry - r.expiry_date end,
         calc.adjusted_expiry is not null and r.expiry_date is not null
           and calc.adjusted_expiry < r.expiry_date,
         r.holiday_country is null,
         public.therapy_calendar_gaps(r.activation_date,
           coalesce(calc.adjusted_expiry, r.expiry_date), r.holiday_country, r.holiday_region)
    from rows r
    left join public.customers c on c.id = r.customer_id
    cross join lateral public.therapy_adjusted_expiry(
                 r.activation_date, r.duration_months, r.holiday_country, r.holiday_region, r.k) calc
   where (p_customer_id is null or r.customer_id = p_customer_id)
     and (public.is_manager_or_above() or public.current_user_role() is not null)
   order by r.k, r.activation_date desc nulls last
$function$;

-- Apply the recalculation. Lengthening happens; shortening does not, unless an
-- Owner or Manager says so explicitly with a reason, one entitlement at a time.
create or replace function public.therapy_apply_recalculation(
  p_kind text default null, p_customer_id uuid default null,
  p_allow_shortening boolean default false, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = public as $function$
declare
  r record; v_updated integer := 0; v_skipped_short integer := 0;
  v_skipped_country integer := 0; v_unchanged integer := 0; v_tbl text;
begin
  if not public.is_manager_or_above() then
    raise exception 'Only an Owner or Manager can recalculate expiry dates';
  end if;
  if p_allow_shortening and coalesce(nullif(btrim(p_reason), ''), '') = '' then
    raise exception 'Shortening a granted expiry requires a reason';
  end if;

  for r in select * from public.therapy_recalculation_preview(p_kind, p_customer_id) loop
    -- No country, no calendar, no change. Reported, not guessed at.
    if r.needs_country then v_skipped_country := v_skipped_country + 1; continue; end if;
    if r.proposed_expiry is null or r.proposed_expiry = r.current_expiry then
      v_unchanged := v_unchanged + 1; continue; end if;
    if r.shortens and not p_allow_shortening then
      v_skipped_short := v_skipped_short + 1; continue; end if;

    v_tbl := case r.entitlement_kind when 'purchased'
               then 'purchased_therapy_entitlements' else 'therapy_entitlements' end;
    execute format($f$
      update public.%I set expiry_date = $1, base_expiry_date = $2,
             closure_days_added = $3, expiry_calculated_at = now() where id = $4
    $f$, v_tbl) using r.proposed_expiry, r.base_expiry, r.days_added, r.entitlement_id;

    insert into public.therapy_expiry_adjustments (
      entitlement_kind, entitlement_id, customer_id, action, reason,
      old_expiry, new_expiry, base_expiry, days_added, performed_by, detail)
    values (r.entitlement_kind, r.entitlement_id, r.customer_id, 'recalculated',
      nullif(btrim(p_reason), ''), r.current_expiry, r.proposed_expiry, r.base_expiry,
      r.days_added, auth.uid(),
      jsonb_build_object('country', r.holiday_country, 'region', r.holiday_region,
                         'shortened', r.shortens, 'coverage', r.coverage));
    v_updated := v_updated + 1;
  end loop;

  return jsonb_build_object('updated', v_updated, 'unchanged', v_unchanged,
    'skipped_needs_country', v_skipped_country, 'skipped_would_shorten', v_skipped_short);
end $function$;

-- ---------------------------------------------------------------------
-- 9. Calendar administration, and who it affects.
-- ---------------------------------------------------------------------
create or replace function public.upsert_therapy_closure_date(
  p_id uuid, p_date date, p_kind text, p_name text,
  p_country text default null, p_region text default null,
  p_observed_for date default null, p_source text default null,
  p_source_reference text default null, p_reason text default null)
returns uuid language plpgsql security definer set search_path = public as $function$
declare v_id uuid;
begin
  if not public.is_manager_or_above() then
    raise exception 'Only an Owner or Manager can edit the holiday calendar';
  end if;
  if p_date is null then raise exception 'A date is required'; end if;
  if coalesce(nullif(btrim(p_name), ''), '') = '' then raise exception 'A name is required'; end if;

  if p_id is null then
    insert into public.therapy_closure_dates
      (closure_date, kind, name, country_code, region, observed_for, source, source_reference, reason, created_by)
    values (p_date, p_kind, btrim(p_name), p_country, p_region, p_observed_for,
            p_source, p_source_reference, p_reason, auth.uid())
    returning id into v_id;
  else
    update public.therapy_closure_dates
       set closure_date = p_date, kind = p_kind, name = btrim(p_name), country_code = p_country,
           region = p_region, observed_for = p_observed_for, source = p_source,
           source_reference = p_source_reference, reason = p_reason,
           updated_by = auth.uid(), updated_at = now()
     where id = p_id and deleted_at is null
    returning id into v_id;
    if v_id is null then raise exception 'That calendar entry no longer exists'; end if;
  end if;
  return v_id;
end $function$;

create or replace function public.delete_therapy_closure_date(p_id uuid, p_reason text default null)
returns void language plpgsql security definer set search_path = public as $function$
begin
  if not public.is_manager_or_above() then
    raise exception 'Only an Owner or Manager can edit the holiday calendar'; end if;
  update public.therapy_closure_dates
     set deleted_at = now(), updated_by = auth.uid(), updated_at = now(),
         reason = coalesce(nullif(btrim(p_reason), ''), reason)
   where id = p_id and deleted_at is null;
end $function$;

-- Who a calendar change would move, before it is made. Removing a date can
-- shorten an expiry, and that must be seen rather than discovered later.
create or replace function public.therapy_closure_impact(
  p_date date, p_country text default null, p_region text default null)
returns table (entitlement_kind text, entitlement_id uuid, entitlement_no text,
               customer_name text, status text, current_expiry date, days_added integer)
language sql stable security definer set search_path = public as $function$
  select p.entitlement_kind, p.entitlement_id, p.entitlement_no, p.customer_name,
         p.status, p.current_expiry, p.days_added
    from public.therapy_recalculation_preview(null, null) p
   where p.activation_date <= p_date
     and coalesce(p.proposed_expiry, p.current_expiry) >= p_date
     and (p_country is null or p.holiday_country = p_country)
     and (p_region is null or p.holiday_region is not distinct from p_region)
$function$;

create or replace function public.set_therapy_calendar_coverage(
  p_country text, p_year integer, p_region text default '*',
  p_verified boolean default true, p_source text default null,
  p_source_reference text default null, p_notes text default null)
returns void language plpgsql security definer set search_path = public as $function$
begin
  if not public.is_manager_or_above() then
    raise exception 'Only an Owner or Manager can confirm calendar coverage'; end if;
  insert into public.therapy_calendar_coverage
    (country_code, year, region, is_verified, source, source_reference, notes, confirmed_by, confirmed_at)
  values (p_country, p_year, coalesce(p_region, '*'), p_verified, p_source, p_source_reference,
          p_notes, auth.uid(), now())
  on conflict (country_code, year, region) do update
    set is_verified = excluded.is_verified, source = excluded.source,
        source_reference = excluded.source_reference, notes = excluded.notes,
        confirmed_by = excluded.confirmed_by, confirmed_at = excluded.confirmed_at;
end $function$;

-- ---------------------------------------------------------------------
-- 10. Access. Reading a calendar is harmless; changing one is not.
-- ---------------------------------------------------------------------
alter table public.therapy_holiday_countries enable row level security;
alter table public.therapy_closure_dates     enable row level security;
alter table public.therapy_calendar_coverage enable row level security;
alter table public.therapy_expiry_adjustments enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where tablename = 'therapy_holiday_countries' and policyname = 'read_countries') then
    create policy read_countries on public.therapy_holiday_countries for select to authenticated using (true);
  end if;
  if not exists (select 1 from pg_policies where tablename = 'therapy_closure_dates' and policyname = 'read_closures') then
    create policy read_closures on public.therapy_closure_dates for select to authenticated using (true);
  end if;
  if not exists (select 1 from pg_policies where tablename = 'therapy_calendar_coverage' and policyname = 'read_coverage') then
    create policy read_coverage on public.therapy_calendar_coverage for select to authenticated using (true);
  end if;
  if not exists (select 1 from pg_policies where tablename = 'therapy_expiry_adjustments' and policyname = 'read_adjustments') then
    create policy read_adjustments on public.therapy_expiry_adjustments for select to authenticated using (true);
  end if;
end $$;

-- Writes go through the SECURITY DEFINER functions above, which check the role.
-- No insert/update/delete policy exists, so a direct table write is refused.

grant select on public.therapy_holiday_countries, public.therapy_closure_dates,
                public.therapy_calendar_coverage, public.therapy_expiry_adjustments to authenticated;

grant execute on function public.therapy_applicable_closures(date,date,text,text) to authenticated;
grant execute on function public.therapy_base_expiry(date,integer,text) to authenticated;
grant execute on function public.therapy_adjusted_expiry(date,integer,text,text,text) to authenticated;
grant execute on function public.therapy_expiry_explanation(date,integer,text,text,text) to authenticated;
grant execute on function public.therapy_calendar_gaps(date,date,text,text) to authenticated;
grant execute on function public.therapy_assign_holiday_country(text,uuid,text,text,text,text) to authenticated;
grant execute on function public.therapy_preview_country_change(text,uuid,text,text) to authenticated;
grant execute on function public.therapy_recalculation_preview(text,uuid) to authenticated;
grant execute on function public.therapy_apply_recalculation(text,uuid,boolean,text) to authenticated;
grant execute on function public.upsert_therapy_closure_date(uuid,date,text,text,text,text,date,text,text,text) to authenticated;
grant execute on function public.delete_therapy_closure_date(uuid,text) to authenticated;
grant execute on function public.therapy_closure_impact(date,text,text) to authenticated;
grant execute on function public.set_therapy_calendar_coverage(text,integer,text,boolean,text,text,text) to authenticated;
